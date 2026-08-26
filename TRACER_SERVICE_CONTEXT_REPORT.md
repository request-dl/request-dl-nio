# `ServiceContext` propagation is lost before span start in `async-http-client`

Status: drafted from RequestDL, not yet filed upstream.
Target repo: `swift-server/async-http-client`.
Discovered while implementing request-scoped `ServiceContext` binding for RequestDL
(https://github.com/orgs/request-dl/discussions/284), see [Origin in RequestDL](#origin-in-requestdl) below.

## Implementation plan

For whoever picks this up next, on the dedicated fork branch. Ordered by priority — do items in
order, each is a separate issue/PR against `swift-server/async-http-client`, don't bundle them (see
why in item 3's notes).

1. **Fix `ServiceContext.current` loss before span start (Gap #1 — the actual bug).**
   Highest priority: it's a genuine correctness bug, not a design-philosophy conflict, and it affects
   *every* consumer of `HTTPClient.Configuration.tracing.tracer`, both API surfaces. Full trace in
   [Root cause](#root-cause-traced-through-the-call-chain).
   - Preferred approach: capture `ServiceContext.current` once in `RequestBag.init`
     (`RequestBag.swift`) — the caller's task-local is still reliably visible there, before any
     `EventLoop.execute` hop happens — and thread it explicitly into
     `startRequestSpan(tracer:context:)` (`RequestBag+Tracing.swift`) instead of relying on
     `Tracer.startSpan`'s implicit `ServiceContext.current` default. This touches only the tracing
     path, not `NIOLoopBound+Execute.swift` (general-purpose plumbing used well beyond tracing, so
     patching it has a much wider review surface and blast radius — avoid that route unless this one
     turns out not to work).
   - File as an issue first with the reproduction from [Reproduction](#reproduction), let a
     maintainer confirm the diagnosis before investing in the PR — this is a subtle enough
     cross-cutting-concerns bug that it's worth a maintainer sanity-check on the fix location before
     writing it.
   - Once fixed upstream and released, RequestDL needs no changes at all —
     `RequestServiceContext`/`RawTask.result()`'s bind already does the right thing on RequestDL's
     side; only remove the `withKnownIssue` wrap on
     `RequestServiceContextTests.dataTask_whenServiceContextSet_shouldBeObservedByTracerDuringExecution`
     and update `RequestServiceContext`'s doc comment to drop the warning.

2. **Decide the strategy for Gap #2 (no header injection on the legacy delegate API) — likely a
   RequestDL-side call, not an async-http-client PR.**
   Two options, pick one:
   - (a) Ask upstream to backport `tracer.inject(...)` into the delegate-based
     `execute(request:delegate:)` path. Lower odds of a quick yes than item 1: maintainers may
     reasonably respond "that API predates tracing support and is being superseded by
     `HTTPClientRequest`, migrate instead" — the delegate-based `execute` overloads aren't deprecated
     but the newer async API is clearly where feature investment goes (see #862, #906 — both only
     touch `AsyncAwait/`).
   - (b) Migrate RequestDL's own request execution (`Internals.Client.execute`,
     `Sources/RequestDLInternals/Sources/Client/Client/Internals.Client.swift`) from the delegate-based
     API onto `HTTPClientRequest`/`execute() async`. This is the RequestDL-side option — no upstream
     dependency, gets header injection "for free" once done, but is a real migration (delegate
     callbacks → async streaming), not a small change. Worth checking whether this overlaps with
     the already-tracked `feature/urlsession-executor` branch's scope before starting it as separate
     work.
   - Recommendation: don't file anything upstream for this until (a) vs (b) is decided — filing (a)
     and then doing (b) anyway wastes a maintainer's review time on a PR RequestDL wouldn't end up
     needing.

3. **Only after 1 (and optionally 2) land: the narrow `attributeKeys` value fix, scoped tightly.**
   Just the `responseStatusCode` default: `http.status_code` → `http.response.status_code`
   (`HTTPClient.swift:1153`), referencing
   [issue #860](https://github.com/swift-server/async-http-client/issues/860) directly. No new public
   API, no configuration surface — see
   [why that distinction matters](#appendix-tracingconfigurationattributekeys--why-making-it-public-is-not-a-viable-ask).
   **Do not bundle in the other attributes from PR #881** (`url.path`, `server.hostname`,
   `network.protocol.version`, etc.) **and especially not `http.request.header`/`http.response.header`**
   — the header-attribute additions are the most plausible source of PR #881's "previously agreed
   upon approach" objection from `fabianfett` (verbose, PII-adjacent, a bigger design call than a
   rename), and bundling a safe rename together with a contentious addition risks blocking the safe
   part too. If maintainers want the other attributes added incrementally after this lands, that's a
   separate PR per attribute (or a small batch of the clearly uncontroversial structural ones —
   `url.path`, `url.scheme`, `server.hostname`, `server.port`, `network.protocol.version` — kept
   separate from the header-content ones either way).

4. **Do not pursue: making `AttributeKeys`/`attributeKeys` `public` or otherwise customizable.**
   Confirmed dead-on-arrival — see the appendix. Skip straight to item 3's values-only fix instead.

## Versions

| Package | Version resolved |
|---|---|
| `swift-server/async-http-client` | 1.36.0 (commit `9544287b9416c0bc71e58b9f3aead8dd14b16103`) |
| `apple/swift-distributed-tracing` | 1.4.1 |
| `apple/swift-nio` | 2.101.3 |
| Swift tools | 6.2 |

## Summary

`HTTPClient.Configuration.tracing.tracer` lets a caller configure a `Tracer` (from
`swift-distributed-tracing`) for the client. The intended behavior — per the doc comment on
`Tracer/startSpan` and the whole design of `ServiceContext` — is that the span each request starts
picks up `ServiceContext.current` (a Swift `@TaskLocal`) as its parent, so a caller can bind a
specific context around a request (e.g. one extracted from an inbound server request) and have
AsyncHTTPClient's own span nest correctly under it.

**This does not happen.** `ServiceContext.current`, bound via
`ServiceContext.$current.withValue(context) { try await client.execute(...) }` around the call, is
reliably `nil` (or whatever was ambient *before* the bind) by the time AsyncHTTPClient actually
calls `tracer.startSpan(...)`. Empirically confirmed with a real client/server round trip — see
[Reproduction](#reproduction).

Root cause: **the span is started only after execution hops onto a `SwiftNIO` `EventLoop` via
`EventLoop.execute(_:)`, and Swift's task-locals do not cross that hop.** Task-locals propagate
through the Swift Concurrency task hierarchy (`Task`, structured-concurrency child tasks,
`withTaskGroup`, `withCheckedContinuation`, plain `async`/`await` calls within the same task) —
never through arbitrary closures scheduled on a `NIOCore.EventLoop`, which is exactly how
AsyncHTTPClient dispatches request execution onto its connection pool.

## Root cause, traced through the call chain

All line numbers are against async-http-client `1.36.0`.

1. **`HTTPClient.execute(request:delegate:...)`** synchronously constructs a `RequestBag` and hands
   it to the pool manager (`HTTPClient.swift:806-822`):
   ```swift
   let requestBag = try RequestBag(request: request, ..., delegate: delegate)
   ...
   self.poolManager.executeRequest(requestBag)
   ```
   This part runs on the caller's own execution context — if called from inside
   `ServiceContext.$current.withValue(context) { ... }`, `ServiceContext.current` is correctly
   `context` up to this point. (The same is true for the newer async `HTTPClientRequest` API: it
   also reaches this point synchronously within the calling task.)

2. **`HTTPConnectionPool.Manager.executeRequest`** (`HTTPConnectionPool+Manager.swift:54-83`) looks
   up or creates the pool for the request's key, still synchronously, and calls
   `pool.executeRequest(request)`.

3. **`HTTPConnectionPool.executeRequest`** (`HTTPConnectionPool.swift:87-89`):
   ```swift
   func executeRequest(_ request: HTTPSchedulableRequest) {
       self.modifyStateAndRunActions { $0.executeRequest(.init(request)) }
   }
   ```
   still synchronous, ultimately reaching the per-connection dispatch at
   `HTTPConnectionPool.swift:694-701`:
   ```swift
   fileprivate func executeRequest(_ request: HTTPExecutableRequest) {
       switch self._ref {
       case .http1_1(let connection):
           return connection.executeRequest(request)
       ...
   ```

4. **`HTTP1Connection.Async.executeRequest`** (`ConnectionPool/HTTP1/HTTP1Connection.swift:86-89`) —
   this is where propagation breaks:
   ```swift
   func executeRequest(_ request: HTTPExecutableRequest) {
       self.connection.execute {
           $0.execute0(request: request)
       }
   }
   ```
   `self.connection` is a `NIOLoopBound<HTTP1Connection>`. `.execute(_:)` on it is defined in
   `NIOLoopBound+Execute.swift:17-28`:
   ```swift
   extension NIOLoopBound {
       @inlinable
       func execute(_ body: @Sendable @escaping (Value) -> Void) {
           if self.eventLoop.inEventLoop {
               body(self.value)
           } else {
               self.eventLoop.execute {
                   body(self.value)
               }
           }
       }
   }
   ```
   Unless the calling thread already happens to be the connection's own `EventLoop` thread — which
   it essentially never is for a request kicked off from Swift Concurrency, since `async`/`await`
   code resumes on the cooperative thread pool, not on one of AsyncHTTPClient's dedicated
   `EventLoop` threads — this dispatches `body` via `self.eventLoop.execute { ... }`. That is a
   plain `@Sendable () -> Void` closure scheduled on a `NIOCore.EventLoop`, with zero relationship
   to the Swift Concurrency task-local stack.

5. Once on the connection's event loop, `execute0` eventually calls back into
   `RequestBag.willExecuteRequest(_:)` (`RequestBag.swift:511-519`), which has **the exact same
   pattern again**:
   ```swift
   func willExecuteRequest(_ executor: HTTPRequestExecutor) {
       if self.task.eventLoop.inEventLoop {
           self.willExecuteRequest0(executor)
       } else {
           self.task.eventLoop.execute {
               self.willExecuteRequest0(executor)
           }
       }
   }
   ```
   `self.task.eventLoop` may not even be the same loop as the connection's — a second possible hop.

6. **`willExecuteRequest0`** (`RequestBag.swift:137-139`) is where the span actually starts:
   ```swift
   private func willExecuteRequest0(_ executor: HTTPRequestExecutor) {
       ...
       self.loopBoundState.value.startRequestSpan(tracer: self.anyTracer)
   }
   ```
   which calls into `RequestBag+Tracing.swift:24-35`:
   ```swift
   mutating func startRequestSpan(tracer: (any Sendable)?) {
       guard #available(...), let tracer = tracer as! (any Tracer)? else { return }
       ...
       self.activeSpan = tracer.startSpan("\(request.method)", ofKind: .client)
   }
   ```
   No explicit `context:` argument is passed, so this resolves to `Tracer`'s default parameter
   (`swift-distributed-tracing`, `Sources/Tracing/Tracer.swift:46`):
   ```swift
   context: @autoclosure () -> ServiceContext = .current ?? .topLevel,
   ```
   By this point, execution has crossed one or two `EventLoop.execute` hops away from the original
   task. `ServiceContext.current` reads whatever is task-local *on the thread this closure happens
   to run on* — which has no relationship to the Swift task that called `execute(request:...)`, so
   it is `nil` (falling back to `.topLevel`) regardless of what the caller bound.

## Contrast: the newer async API *does* inject correctly, but only because it runs earlier

`HTTPClientRequest.Prepared.init` (`AsyncAwait/HTTPClientRequest+Prepared.swift:71-75`) does read
`ServiceContext.current` correctly:
```swift
if let tracer = tracing?.tracer, let context = ServiceContext.current {
    tracer.inject(context, into: &headers, using: HTTPHeadersInjector.shared)
}
```
This works only because it runs **before** the request ever reaches the connection pool — it's part
of preparing the `HTTPClientRequest` into `Prepared` form, synchronously within the caller's own
task, at the `execute()` call site. It has nothing to do with `RequestBag`/`willExecuteRequest0`, and
does not fix the span-parenting issue in [Root cause](#root-cause-traced-through-the-call-chain):
that code path still starts the span later, after the same `EventLoop` hops, so **even a caller
using the modern async API gets correctly-injected trace headers on the wire, but an incorrectly
un-parented span locally** (it'll show up in the exporting backend as a new trace root, not nested
under the caller's context, unless the tracer's own `inject`/wire format is what a downstream
service uses to reconstruct the relationship rather than the local parent-span link).

## Two distinct gaps

1. **Bug — span-start loses the task-local `ServiceContext.current`.** Affects *every* consumer of
   `HTTPClient.Configuration.tracing.tracer`, both the delegate-based `execute(request:delegate:)`
   API and the modern `execute() async` API. This is the one demonstrated by the reproduction below.

2. **Gap — the delegate-based `execute(request:delegate:)` API never injects trace headers at all.**
   `tracer.inject(context:into:using:)` is called exactly once in the whole package, inside
   `HTTPClientRequest.Prepared.init` (`AsyncAwait/HTTPClientRequest+Prepared.swift:74`), which only
   the modern async API path constructs. A caller using the older delegate-based `execute` (as
   RequestDL currently does — see below) gets no `traceparent`/`tracestate` header injected into
   the outgoing request under any circumstances, independent of gap #1.

## Reproduction

Minimal repro shape (Swift Testing), using a real local HTTP server:

```swift
final class ContextCapturingTracer: Tracer, Sendable {
    private let box = NIOLockedValueBox<String?>(nil)
    var capturedTestID: String? { box.withLockedValue { $0 } }

    func startSpan<Instant: TracerInstant>(
        _ operationName: String,
        context: @autoclosure () -> ServiceContext,
        ofKind kind: SpanKind,
        at instant: @autoclosure () -> Instant,
        function: String, file fileID: String, line: UInt
    ) -> NoOpTracer.NoOpSpan {
        let resolved = context()
        box.withLockedValue { $0 = resolved.testID }   // custom ServiceContextKey
        return NoOpTracer.NoOpSpan(context: resolved)
    }

    func forceFlush() {}
    func inject<C, I: Injector>(_ context: ServiceContext, into carrier: inout C, using injector: I) where I.Carrier == C {}
    func extract<C, E: Extractor>(_ carrier: C, into context: inout ServiceContext, using extractor: E) where E.Carrier == C {}
}

var configuration = HTTPClient.Configuration()
configuration.tracing.tracer = ContextCapturingTracer()
let client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)

var context = ServiceContext.topLevel
context.testID = "trace-abc"

try await ServiceContext.$current.withValue(context) {
    _ = try await client.execute(
        request: try HTTPClient.Request(url: "http://127.0.0.1:PORT/"),
        delegate: ResponseAccumulator(request: ...)
    ).futureResult.get()
}

// FAILS: tracer.capturedTestID is nil, not "trace-abc"
#expect(tracer.capturedTestID == context.testID)
```

RequestDL's actual reproduction, exercised against `.build/checkouts` at the versions above, is at
[`Tests/RequestDLTests/Properties/Sources/Tracing/Service Context/RequestServiceContextTests.swift`](Tests/RequestDLTests/Properties/Sources/Tracing/Service%20Context/RequestServiceContextTests.swift),
test `dataTask_whenServiceContextSet_shouldBeObservedByTracerDuringExecution`. It does a warm-up
request first specifically to rule out "cold connection, so of course it needs to queue and hop
threads" as an alternative, simpler explanation — the failure is deterministic even against an
already-idle, previously-used connection, which matches the root cause above (the hop happens
unconditionally in `NIOLoopBound.execute`, gated only on which thread happens to be running the
calling code at that instant — not on whether the connection was already established).

## Suggested fix direction (not implemented, for upstream discussion)

The general shape: capture `ServiceContext.current` at each of the two `EventLoop.execute` hops
identified above (`NIOLoopBound+Execute.swift:19-27` and `RequestBag.swift:511-519`) and rebind it
inside the dispatched closure, e.g.:

```swift
func execute(_ body: @Sendable @escaping (Value) -> Void) {
    let context = ServiceContext.current
    if self.eventLoop.inEventLoop {
        body(self.value)
    } else {
        self.eventLoop.execute {
            ServiceContext.$current.withValue(context) {
                body(self.value)
            }
        }
    }
}
```
This is package-wide plumbing (`NIOLoopBound+Execute.swift` is a general-purpose helper used well
beyond the tracing path), so capturing/rebinding `ServiceContext.current` there has to be weighed
against the cost of doing so on every hop, tracing enabled or not — an alternative is threading the
captured context explicitly through `RequestBag` itself (capture it once in `RequestBag.init`,
where the caller's task-local is still reliably visible, and pass it explicitly into
`startRequestSpan(tracer:context:)` instead of relying on `Tracer`'s implicit default). That version
touches less shared code and only pays a `ServiceContext.current` read once per request instead of
once per hop.

## Origin in RequestDL

RequestDL added `Session().tracer(_:)` (binds a `Tracer`) and attempted to add
`RequestServiceContext(_:)` (a per-request `Property` meant to bind `ServiceContext.current` around
that one request's execution, for callers whose code isn't already running in the task where the
right context is ambient — e.g. a background queue or a job picked up from another subsystem). The
binding itself
([`Sources/RequestDL/Tasks/Sources/Raw Task/Raw/RawTask.swift`](Sources/RequestDL/Tasks/Sources/Raw%20Task/Raw/RawTask.swift))
and the property
([`Sources/RequestDL/Properties/Sources/Tracing/Service Context/RequestServiceContext.swift`](Sources/RequestDL/Properties/Sources/Tracing/Service%20Context/RequestServiceContext.swift))
are implemented and unit-tested for what RequestDL itself controls (the `RequestConfiguration`
plumbing, the task-local bind around `RawTask.result()`), but as documented on
`RequestServiceContext` itself, they currently have **no observable effect** on AsyncHTTPClient's
own span or on the outgoing request's headers, for the reasons in this report — both gaps live
entirely inside `async-http-client`, not in anything RequestDL controls. RequestDL is also affected
by gap #2 specifically because it currently executes requests through the legacy delegate-based
`execute(request:delegate:)` API rather than the modern `HTTPClientRequest` async API.

This report exists so the fix can be pursued upstream; RequestDL's side is left in place (harmless,
already correctly documented as currently ineffective) so it starts working with no further RequestDL
changes once gap #1 is fixed there, and so `RequestServiceContext` is ready to also inject headers
once/if RequestDL migrates its execution path to close gap #2 as well.

## Appendix: `TracingConfiguration.attributeKeys` — why making it public is not a viable ask

Separate from the `ServiceContext` propagation bug above, the original RequestDL discussion
(https://github.com/orgs/request-dl/discussions/284) also listed `TracingConfiguration.attributeKeys`
customization as out of scope, since it's `package`-visibility in `async-http-client` with a
`// TODO: Open up customization of keys we use?` comment. Before pursuing a PR to make it `public`,
checked the project's actual issue/PR history for how the maintainers have handled this exact class of
request. **They have already, explicitly and recently, rejected it.**

### The maintainers have a stated anti-configuration-knob philosophy for tracing attributes

[PR #906](https://github.com/swift-server/async-http-client/pull/906) ("Set `url.full` attribute on
spans logged for HTTP requests", merged 2026-07-27) originally included an opt-in/opt-out
configuration option for the new attribute. The response:

> **czechboy0** (2026-06-05): "I think `url.full` should be enabled by default, following
> OpenTelemetry standard attributes [...] Almost any string field can, in theory, have PII, and I
> think this is the wrong place to try to make that call. Let application owners filter PII in their
> telemetry backends instead."

> **ktoso**, author of `swift-distributed-tracing` (2026-06-08): "Agree on not doing tens of settings
> in the lib itself, collectors can handle that 👍"

The contributor removed the configuration option from the PR in direct response
(2026-06-05 comment: "Updated the PR to remove the configuration options.") before it was merged.
This is a stated design position, not an oversight: attribute-level customization belongs in the
telemetry collector/backend, not as knobs on `HTTPClient.Configuration`. Making `AttributeKeys`
`public` (with setters) is exactly the shape of change this rejects.

### A PR attempting this exact change has been stuck for 7+ months

[PR #881](https://github.com/swift-server/async-http-client/pull/881) ("Add more span attributes
(URL, network)", opened 2026-01-21, still open, `mergeable: CONFLICTING`) implements several of the
attributes requested in [issue #860](https://github.com/swift-server/async-http-client/issues/860)
("[Tracing] Add more span attributes", `good first issue`, opened by ktoso), including changing
`responseStatusCode`'s default from the legacy `http.status_code` to the current
`http.response.status_code` — the exact semconv drift this report's author independently noticed by
reading `HTTPClient.swift:1149-1155` before finding this issue. A maintainer with write access
blocked it:

> **fabianfett** (MEMBER, 2026-02-20): "I'm fine with adding the additional tracing attributes.
> However I'm not a fan of changing the previously agreed upon approach to tracing."

No further commits since 2026-03-23; the PR has sat unresolved since. So even a change that doesn't
add new public API — just correcting a stale default value — has not landed cleanly, for reasons tied
to some "previously agreed upon approach" not stated in the thread.

### What this means for `attributeKeys`

- **Making `AttributeKeys`/`attributeKeys` `public` and settable is very likely dead on arrival.** It
  is precisely the "tens of settings in the lib itself" pattern maintainers rejected in #906, days to
  weeks before this was written. Do not lead with this ask.
- **The one narrower thing that's arguably still aligned with what maintainers want**: issue #860
  itself, filed by ktoso, explicitly asks for more/corrected span attributes — including the
  `http.status_code` → `http.response.status_code` rename — as *default value* fixes, not new
  configuration surface. That is a much smaller, values-only change with no new public API. It is
  still not guaranteed smooth (see PR #881's stall over "previously agreed upon approach"), so it is
  worth scoping as tightly as possible — ideally just the one rename, referencing #860 directly,
  rather than bundling in the other attributes #881 tried to add at once.
- Versions referenced above: `swift-server/async-http-client` main branch and PR/issue state as of
  2026-08-25; the package RequestDL depends on is `1.36.0` (tagged 2026-07-23), which already
  includes #862 (async-API header injection) but predates #906.
