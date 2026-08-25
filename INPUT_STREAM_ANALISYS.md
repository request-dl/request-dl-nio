# `InputStream` / `uploadTask(withStreamedRequest:)` Investigation Brief

**Status:** Root cause narrowed to a specific, reproducible CFNetwork behavior; not yet fixed, not yet reported to Apple, not yet worked around. This document hands the investigation to a fresh session/agent with **no prior context** of how it got here — read it in full before touching code. Everything in "What's already ruled out" was *run*, not reasoned about; don't re-derive it, and don't trust any claim in `URLSESSION_TASK.md`/`URLSESSION_REPORT.md` about this specific bug that predates this document — one of them was wrong (see §2).

## 1. Where this comes from

`request-dl-nio` (this repo) is adding `URLSession` as a third HTTP executor alongside SwiftNIO-based ones (`URLSESSION_TASK.md`, `URLSESSION_REPORT.md` — read those for the broader project if useful, but they are not required to understand this specific bug). Phase 5f of that plan built `Internals.URLSessionClient` (`Sources/RequestDLInternals/Sources/Client/URLSession Client/Internals.URLSessionClient.swift`) so a request body can be **streamed** into `URLSession` rather than fully buffered first, via `uploadTask(withStreamedRequest:)` + `URLSessionTaskDelegate.urlSession(_:task:needNewBodyStream:)`. That delegate callback must hand back a plain `InputStream`; RequestDL built one (`Internals.URLSessionUploadStream`, `Sources/RequestDLInternals/Sources/Client/URLSession Client/Upload/Internals.URLSessionUploadStream.swift`) that bridges an `AsyncSequence<ByteBuffer>` (its own push-model body representation) into that pull-model `InputStream` contract.

That bridge hangs. Every streamed-upload integration test in the repo (`RequestConfigurationURLSessionClientUploadTests`, `InternalsURLSessionClientSessionTaskTests`) is currently `withKnownIssue`-wrapped because of it. This document is the result of a same-day investigation (2026-08-24) that went well past what those tests' comments currently say, using throwaway diagnostics outside the main test suite (all since deleted — nothing in this repo's git history reflects the diagnostics below except this file; the code snippets here are transcribed from what was actually run and observed).

## 2. The bug, precisely

`uploadTask(withStreamedRequest:)`, on the OS build this was tested on (see §3), silently opts every streamed upload into an experimental IETF draft, ["resumable uploads"](https://datatracker.ietf.org/doc/draft-ietf-httpbis-resumable-upload/) — the outgoing request carries `Upload-Draft-Interop-Version: 6` and `Upload-Complete: ?1` headers nobody asked for. This part was already known before this document (see `RequestConfigurationURLSessionClientUploadTests.swift`'s type doc comment) — what was **not** known, and is the actual point of this investigation:

- The client sends the **entire** request body successfully — confirmed server-side, byte-for-byte, every time.
- The client then **never signals end-of-body** to the server (no chunked terminator over HTTP/1.1, no `END_STREAM` flag over HTTP/2) and never calls `read()` on the `InputStream` again to check for more data/EOF.
- The task just sits there until `URLSessionConfiguration.timeoutIntervalForRequest` fires client-side, at which point it sends `RST_STREAM(CANCEL)` (HTTP/2) or closes the connection (HTTP/1.1) and completes with `NSURLErrorTimedOut` (-1001).
- **This reproduces with a bare, from-Foundation `InputStream(data:)` — Apple's own concrete class — supplied to the exact same `needNewBodyStream` callback: it does NOT hang.** It completes in well under a second, against every server this was tried against (§4). Only a **custom `InputStream` subclass** triggers the hang — confirmed with three independently-written subclasses (RequestDL's real one, an earlier broken hand-rolled one, and a deliberately minimal "textbook" one, §4.6).
- **The previously-documented claim that a real external server (httpbin.org) works** (in `RequestConfigurationURLSessionClientUploadTests.swift`'s comment, inherited from Phase 5f) is **misleading, not wrong on its own terms**: it was true only for a bare `InputStream(data:)` probe, never re-tested with RequestDL's actual `Internals.URLSessionUploadStream`. Re-tested in this investigation: **httpbin.org also hangs** with the real bridge. Nothing about "real server vs. local server" or "internet vs. loopback" explains this bug — see §4.3–§4.5. Correct `URLSESSION_TASK.md`/any test comments that still say otherwise once this is resolved.

## 3. Environment this was observed in

- macOS, Xcode-beta.app toolchain, SDK `macosx27.0` (i.e. an unreleased/beta major OS — "AppleOS 27" was not yet released as of this writing; see `URLSESSION_TASK.md`'s own note on this under Phase 5c).
- `User-Agent` observed on the wire: `CFNetwork/3896.100.1.1.1 Darwin/27.0.0`.
- Test binary: `swiftpm-testing-helper` (bare `swift test`, unsigned).
- **Not yet checked**: whether this reproduces on a released/stable macOS version, on iOS (simulator or device), or with an older CFNetwork. This matters — if it's beta-OS-specific, the right move might be "wait and re-test," not "engineer around it." Checking this is one of the first things the new investigation should do if a second Mac/OS version is available; if not, note that limitation explicitly rather than silently assuming beta-specific.

## 4. What's already ruled out (each one actually run, not assumed)

### 4.1 Not `LocalServer` (this repo's own hand-rolled NIOHTTP1 test server) specifically
Reproduced against a from-scratch Python `http.server`-based HTTP/1.1 server, written to correctly decode chunked transfer-encoding (the first naive version didn't, and *that* version's false "0 bytes received" result was a red herring from the diagnostic script's own bug, not the actual finding — worth remembering as a lesson: verify the *test harness* handles the wire format correctly before trusting what it reports). Once fixed to decode chunked bodies properly, it showed the same pattern as everything else in this list.

### 4.2 Not HTTP/1.1 vs. HTTP/2
Built two independent HTTP/2 servers and confirmed ALPN actually negotiated `h2` in both (logged directly, not assumed):
- One using `swift-nio-http2`'s `configureHTTP2SecureUpgrade`/`configureHTTP2Pipeline` + `HTTP2FramePayloadToHTTP1ServerCodec` (full working code in §6.1).
- One using Python's `h2` library (sans-io HTTP/2 reference implementation used by e.g. `hypercorn`) driven directly over raw TLS sockets, with **zero** SwiftNIO involvement (full working code in §6.2) — this was deliberately built to rule out a bug in `swift-nio-http2`'s server-side implementation specifically, since RequestDL itself depends on `async-http-client`/SwiftNIO elsewhere.

Both showed the identical pattern: ALPN → `h2`, full body received, `END_STREAM` never sent, `RST_STREAM(CANCEL)` after client timeout.

### 4.3 Not loopback vs. real network interface
Re-ran the Python `h2` server bound to the machine's actual LAN IP (`192.168.0.43`, found via `ipconfig getifaddr en0`) instead of `127.0.0.1`, with a matching self-signed cert (`subjectAltName=IP:192.168.0.43`). Same exact pattern. This was tested specifically because this exact codebase already has a *different*, confirmed CFNetwork quirk where macOS/Catalyst treat `localhost` specially (see `URLSESSION_TASK.md` Phase 5c, proxy bypass for `localhost` specifically) — worth ruling out a similar loopback-specific mechanism here too. It's not that.

### 4.4 Not "real server vs. local server" / not DNS / not certificate trust path
Re-ran the **exact same** streamed-upload call (`Internals.URLSessionClient.execute(request:streaming:)`, RequestDL's real bridge) against `https://httpbin.org/post` directly. **It also hung and timed out**, identically to every local server. This directly contradicts the pre-existing documentation (§2). httpbin.org uses a real, publicly-trusted certificate (default system trust, no custom `URLAuthenticationChallenge` handling needed) — so this also rules out anything related to the custom `AcceptAnyServerTrustDelegate`/self-signed-cert trust override every local test necessarily uses.

### 4.5 Not `Internals.URLSessionUploadStream`'s specific implementation
Built a deliberately minimal, fully synchronous `InputStream` subclass — no concurrency, no async producer task, no bounded buffer, just a `Data` and an integer offset — implementing every documented override "by the book," including `StreamDelegate` event notifications (`.hasBytesAvailable`/`.endEncountered`) that RequestDL's real implementation did *not* have (added them as a hypothesis fix, confirmed they don't help — see next point). Full code in §6.3. **Same exact hang.**

### 4.6 Not (as far as tested) a missing `StreamDelegate` notification
Hypothesis tried: `URLSession` registers itself as the `InputStream`'s `delegate` (confirmed via a crash stack trace from an *earlier, broken* hand-rolled subclass that didn't override `delegate` at all — it crashed with `-setDelegate: only defined for abstract class`, with a native stack trace showing `CFReadStreamSetClient` → `RequestBodyStream::_onqueue_setupStream()` → `HTTPTransaction::bodyStartProvidingData` → `NWIOConnection::writeWithContext`, i.e. CFNetwork's own body-streaming machinery). The hypothesis was that RequestDL's stream needed to proactively call `delegate?.stream?(self, handle: .endEncountered)` when the body is exhausted, since it never did. **Added that call, rebuilt, re-tested against the Python `h2` server: no change, same hang.**

Then found the likely reason the fix couldn't have helped: **in every failing run, `read(_:maxLength:)` is called exactly once.** It's called with a large `maxLength` (e.g. `1_048_576`), returns all the available bytes in one shot (e.g. `4096`), and `URLSession` never calls `read()` a second time — which is the only way this stream would ever have gotten a chance to return `0` and fire `.endEncountered`. So whatever CFNetwork is doing to (fail to) recognize end-of-body for a custom subclass, it is **not** waiting on a second `read()` call or a delegate event this stream can send it *from inside `read()`*. The fix was reverted (see `git log`/this document; the working tree has no trace of it) since it demonstrably doesn't address the actual mechanism and its rationale turned out to be based on a misread of that stack trace.

### 4.7 Confirmed positive control (this is what makes the whole investigation trustworthy)
A bare `InputStream(data:)` — literally `InputStream(data: payload)`, zero custom code — supplied via the exact same `needNewBodyStream` callback, against every server above (Python plain-HTTP `http.server`, the two independent HTTP/2 servers, httpbin.org): **completes normally every time**, typically in well under a second. This is the control that proves the bug is real, specific, and isolated to "custom `InputStream` subclass" as the variable — not a flaky network/environment issue.

### 4.8 Not "being a Swift `InputStream` subclass" specifically — a genuine `CFReadStream` hangs too

Tested in `urlsession-uploadstream-repro` (the standalone SPM package this document asked for — see §7/§9), via `CFReadStreamCreate` (private CoreFoundation SPI: dropped from the public SDK headers around 2014, but the symbol is still exported by `CoreFoundation.tbd` on current SDKs — including the beta SDK this was tested against — so it still links when declared by hand; see `Sources/CFCallbackStream/` in that package for the exact declarations, reconstructed from the last public revision of `CFStreamAbstract.h`). This builds a **genuine `CFReadStream`** — the same underlying object family `InputStream(data:)` itself is built from via `CFReadStreamCreateWithData` — from hand-written C callbacks instead of a Swift subclass, then casts it to `InputStream` via Darwin's toll-free bridging (`CFReadStreamRef` ↔ `NSInputStream`) before handing it to `needNewBodyStream`. The callbacks were written to mirror `MinimalInputStream` (§6.3) as closely as possible: synchronous, in-memory, `getBuffer` declined (returns `NULL`), no real run-loop scheduling beyond counting the call.

**Result: identical hang.** Full body sent (65536/65536 bytes), the `read` callback called exactly once, the `schedule` callback called exactly once, then `NSURLErrorTimedOut` — same as every Swift-subclass variant in §4.5–§4.6, against both the HTTP/1.1 and HTTP/2 servers.

This **falsifies §5's original working theory as stated**: whatever CFNetwork is doing differently for `InputStream(data:)` vs. everything else, it is *not* simply "is this object a genuine, introspectable `CFReadStream`" — our stream *is* one, created through the same primitive API, and it hangs anyway. See §5 (revised) below.

One incidental new fact worth keeping: `schedule` **was** called (once) in this and every subclass variant tested — contradicting the old, never-verified assumption (noted in §8 item 1) that RequestDL's real implementation relied on ("URLSession never schedules the stream on a run loop"). It does call it; whatever it does after doesn't require our schedule callback to do anything, since our callback is a no-op counter and the hang happens regardless.

### 4.9 Not a queryable-length (or any) `copyProperty`/`setProperty` check — CFNetwork never asks

Direct follow-up to §4.8's revised theory, tested the same way (`urlsession-uploadstream-repro`, `CFCallbackStream`): implemented `copyProperty` and `setProperty` for real on the §4.8 stream — not to answer anything (both still return `NULL`/`false`, unchanged behavior) but purely to *log every property name CFNetwork asks for*, in arrival order, both to stderr live and to a queryable list (`CFCallbackStreamGetPropertyQueryCount`/`GetPropertyQueryName`, wrapped as `cfCallbackStreamPropertyQueries(_:)` in Swift). Ran against both the HTTP/1.1 and HTTP/2 servers, letting the request run all the way to timeout.

**Result: zero queries.** `copyProperty` and `setProperty` are never called at all — not once, for any property name — over the entire lifetime of the stream, from `needNewBodyStream` handing it over through the client-side timeout. Confirmed via both the stderr log (nothing printed) and the recorded-query list (empty) for every run.

This **falsifies §5's revised theory too**: CFNetwork isn't failing to detect end-of-body because it queried a length property we didn't answer — it never queries *any* property, so there's no length-discovery step happening through this mechanism at all for a callback-based (or presumably any non-`CFReadStreamCreateWithData`) stream. Whatever `InputStream(data:)` gets that these streams don't, it isn't delivered via `copyProperty`. See §5 (revised again) below. Tests: `cfCallbackStreamHTTP1/HTTP2ReproducesHang` in `UploadStreamReproTests.swift` now assert `cfCallbackStreamPropertyQueries(stream).isEmpty` as a pinned-down regression check on this specific finding.

### 4.10 Not a missing `getBuffer` — CFNetwork never calls it either

Follow-up to §8 item 2, tested two independent ways in `urlsession-uploadstream-repro`: (a) a new Swift `InputStream` subclass, `GetBufferInputStream` (`Sources/UploadStreamRepro/ReproInputStreams.swift`), identical in shape to `MinimalInputStream` except `getBuffer(_:length:)` is answered for real — a direct pointer into an owned, stably-allocated buffer, returning `true` — instead of declined; and (b) `CFCallbackStreamCreateWithGetBuffer` (`Sources/CFCallbackStream/CFCallbackStream.c`), the same genuine-`CFReadStream` construction as §4.8 but with a real `getBuffer` callback instead of `NULL`. Both track a `getBufferCallCount` alongside the existing `readCallCount`/`scheduleCallCount`, so it's directly observable which one (if either) CFNetwork actually calls. Ran all four combinations (subclass/CF-backed × HTTP/1.1/HTTP/2) to timeout.

**Result: `getBufferCallCount` is 0 in every case.** CFNetwork never calls `getBuffer` at all, on either the Swift subclass or the genuine `CFReadStream` — `read(_:maxLength:)` is still the only method it calls (exactly once, as in every prior variant), and the hang is otherwise identical: full body sent, then `NSURLErrorTimedOut`. Tests: `getBufferSubclassHTTP1/HTTP2ReproducesHang` and `getBufferCFCallbackStreamHTTP1/HTTP2ReproducesHang` in `UploadStreamReproTests.swift`, each asserting `getBufferCallCount == 0` as a pinned-down regression check.

This **falsifies the §8 item 2 hypothesis outright**: it's not that CFNetwork would behave differently given the direct-pointer shortcut — it never attempts to use it in the first place, on any custom stream tried so far, regardless of whether the shortcut is offered. See §5 (revised a third time) below.

## 5. Working theory

**Original theory (falsified by §4.8):** CFNetwork's resumable-uploads-draft code path special-cases concrete, first-party `InputStream`-family *objects* it can introspect directly, bypassing the polymorphic `InputStream` interface entirely for those, and falls into a broken/incomplete path for anything else. Ruled out: a genuine `CFReadStream` (not a polymorphic subclass) hangs identically to one.

**First revision (falsified by §4.9):** the distinguishing factor is a queryable **length**, obtained via `copyProperty`, that `InputStream(data:)`'s convenience constructor exposes and callback-based streams don't. Ruled out: CFNetwork never calls `copyProperty` (or `setProperty`) at all before timing out, on a stream that fully implements both.

**Second revision (falsified by §4.10):** the distinguishing factor is CFNetwork taking a different internal code path when a stream offers the `getBuffer` direct-pointer shortcut. Ruled out: `getBuffer` is never called at all, on either a Swift subclass or a genuine `CFReadStream`, whether it's offered or declined — there's no shortcut being taken or not taken, because it's never attempted.

**Where that leaves things (unconfirmed, no new leading hypothesis yet):** three mechanisms are now ruled out — object identity/type-checking (§4.8), property-based length discovery (§4.9), and the `getBuffer` shortcut (§4.10) — as the source of the difference between `InputStream(data:)` and every custom variant tried. Every callback in `CFReadStreamCallBacks` that's plausibly relevant to end-of-body detection has now been implemented for real on at least one variant and made no difference; `read` is called exactly once and `schedule` exactly once in every failing case regardless. What's left, from §8's remaining untested items: (a) real run-loop/dispatch-queue *registration* — `schedule` is called once (§4.8) but every variant's implementation of it is a no-op beyond counting; the next test is to actually register with the run loop and fire `CFReadStreamSignalEvent`/`StreamDelegate` events through it, in case CFNetwork is waiting on an event delivered *through* that scheduling rather than on the scheduling call itself; (b) something entirely outside the `CFReadStreamCallBacks` surface — e.g. a check against the stream's `CFGetTypeID()` / class identity specifically matching `CFReadStreamCreateWithData`'s concrete type (not just "is a `CFReadStream`" as §4.8 tested, but "is *specifically* the data-backed concrete subtype"), which no callback-level instrumentation can surface since it's a different introspection point entirely. (a) is the cheaper, more mechanical next test; (b) would need something like an Instruments trace or symbolicated stack sample during the hang to investigate rather than another callback variant — at this point, with three plausible callback-level mechanisms ruled out, (b) (or §8 item 3's file-backed workaround, which sidesteps the question entirely) is worth weighing more seriously than before.

## 6. Known-good code to start from

Everything below was actually run and behaves as described. Transcribed from the diagnostics (which were deleted after use, per this session's practice of not leaving throwaway diagnostic code in the main repo/test suite). Treat these as a starting point, not a final harness — the new SPM package should absorb and extend these, not necessarily reuse them verbatim.

### 6.1 Minimal HTTP/2 server in Swift (`swift-nio-http2`) — only needed if the new investigation wants a Swift-side server too; §6.2's Python one is likely sufficient and has zero SwiftNIO involvement, which is the more valuable isolation for this repo's purposes

```swift
import NIOCore
import NIOHTTP1
import NIOHTTP2
import NIOPosix
import NIOSSL

// tlsConfiguration needs applicationProtocols = ["h2", "http/1.1"] and a cert+key
// (any self-signed pair with the right SAN works; see LocalServer.TLSOption in this
// repo's Tests/RequestDLTestSupport for a pattern, or generate fresh with openssl).

let channel = try await ServerBootstrap(group: group)
    .childChannelInitializer { channel in
        do {
            try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: sslContext))
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
        }
        return channel.pipeline.configureHTTP2SecureUpgrade(
            h2PipelineConfigurator: { pipeline in
                pipeline.eventLoop.makeFutureWithTask {
                    // NOTE: `channel` here is the outer closure's `channel`, captured --
                    // `configureHTTP2Pipeline` lives on `Channel`, not `ChannelPipeline`
                    // (`pipeline.channel` is `internal`, inaccessible from outside NIOCore).
                    _ = try await channel.configureHTTP2Pipeline(mode: .server) { streamChannel in
                        streamChannel.eventLoop.makeFutureWithTask {
                            try await streamChannel.pipeline.addHandler(HTTP2FramePayloadToHTTP1ServerCodec())
                            try await streamChannel.pipeline.addHandler(MyHTTP1StyleHandler())
                        }
                    }.get()
                }
            },
            http1PipelineConfigurator: { pipeline in
                pipeline.eventLoop.makeFutureWithTask {
                    try await pipeline.addHandler(HTTPResponseEncoder())
                    try await pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder()))
                    try await pipeline.addHandler(MyHTTP1StyleHandler())
                }
            }
        )
    }
    .bind(host: "127.0.0.1", port: 0)
    .get()
```

`MyHTTP1StyleHandler` is a plain `ChannelInboundHandler` with `InboundIn = HTTPServerRequestPart`/`OutboundOut = HTTPServerResponsePart` — `HTTP2FramePayloadToHTTP1ServerCodec` translates HTTP/2 frames into the same wire types a normal NIOHTTP1 handler already speaks, so existing HTTP/1-style handler code (e.g. this repo's own `LocalServer.HTTPHandler`) is close to directly reusable.

**This requires adding `swift-nio-http2` as an explicit package dependency** (it's already present transitively via `async-http-client`, pinned in `Package.resolved` at `1.39.0`, but no target in this repo imports `NIOHTTP2` directly today) — irrelevant for the *new*, separate SPM package this document asks for, but worth knowing if anyone is tempted to prototype inside this repo instead.

### 6.2 Minimal HTTP/2 server in Python (`h2` library) — no SwiftNIO involved at all

```python
#!/usr/bin/env python3
import socket, ssl, sys, threading
import h2.connection, h2.events, h2.config

def handle(conn_socket):
    config = h2.config.H2Configuration(client_side=False)
    conn = h2.connection.H2Connection(config=config)
    conn.initiate_connection()
    conn_socket.sendall(conn.data_to_send())
    received = {}
    while True:
        try:
            data = conn_socket.recv(65535)
        except (ConnectionResetError, ssl.SSLError, OSError) as e:
            sys.stderr.write(f"[server] recv error: {e}\n"); break
        if not data:
            sys.stderr.write("[server] connection closed by peer (no more data)\n"); break
        for event in conn.receive_data(data):
            if isinstance(event, h2.events.RequestReceived):
                sys.stderr.write(f"[server] RequestReceived stream={event.stream_id} headers={event.headers}\n")
                received[event.stream_id] = 0
            elif isinstance(event, h2.events.DataReceived):
                received[event.stream_id] = received.get(event.stream_id, 0) + len(event.data)
                sys.stderr.write(f"[server] DataReceived stream={event.stream_id} chunk={len(event.data)} total={received[event.stream_id]}\n")
                conn.acknowledge_received_data(len(event.data), event.stream_id)
            elif isinstance(event, h2.events.StreamEnded):
                sys.stderr.write(f"[server] StreamEnded stream={event.stream_id} totalReceived={received.get(event.stream_id, 0)}\n")
                body = f'{{"receivedBytes":{received.get(event.stream_id, 0)},"response":"Hello World"}}'.encode()
                conn.send_headers(event.stream_id, [(":status", "200"), ("content-type", "application/json"), ("content-length", str(len(body)))])
                conn.send_data(event.stream_id, body, end_stream=True)
            elif isinstance(event, h2.events.StreamReset):
                sys.stderr.write(f"[server] StreamReset stream={event.stream_id} error_code={event.error_code}\n")
        outbound = conn.data_to_send()
        if outbound:
            conn_socket.sendall(outbound)

def main():
    port, cert, key, bind_addr = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=cert, keyfile=key)
    ctx.set_alpn_protocols(["h2"])
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((bind_addr, port)); sock.listen(5)
    sys.stderr.write(f"[server] listening on {bind_addr}:{port} (h2 only)\n")
    while True:
        client_socket, addr = sock.accept()
        sys.stderr.write(f"[server] accepted connection from {addr}\n")
        try:
            tls_socket = ctx.wrap_socket(client_socket, server_side=True)
            sys.stderr.write(f"[server] ALPN negotiated: {tls_socket.selected_alpn_protocol()}\n")
        except ssl.SSLError as e:
            sys.stderr.write(f"[server] TLS handshake failed: {e}\n"); continue
        threading.Thread(target=handle, args=(tls_socket,), daemon=True).start()

if __name__ == "__main__":
    main()
```

Setup: `python3 -m venv venv && ./venv/bin/pip install h2`, plus a self-signed cert:
`openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 2 -nodes -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1"`.
Run: `./venv/bin/python3 server.py 9092 cert.pem key.pem 127.0.0.1`.

### 6.3 Minimal failing `InputStream` subclass (Swift, pure Foundation)

```swift
final class MinimalInputStream: InputStream, @unchecked Sendable {
    private var data: Data
    private var offset = 0
    private var _status: Stream.Status = .notOpen
    private var _delegate: StreamDelegate?

    override init(data: Data) {
        self.data = data
        super.init(data: Data())
    }

    override var delegate: StreamDelegate? {
        get { _delegate }
        set { _delegate = newValue }
    }
    override var streamStatus: Stream.Status { _status }
    override var streamError: Error? { nil }
    override func open() { _status = .open }
    override func close() { _status = .closed }
    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    override func property(forKey key: Stream.PropertyKey) -> Any? { nil }
    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool { false }
    override var hasBytesAvailable: Bool { offset < data.count }

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        let remaining = data.count - offset
        let n = min(len, remaining)
        if n > 0 { data.copyBytes(to: buffer, from: offset..<(offset + n)); offset += n }
        if n == 0 {
            _status = .atEnd
            _delegate?.stream?(self, handle: .endEncountered)
        } else {
            _delegate?.stream?(self, handle: .hasBytesAvailable)
        }
        print("read maxLength=\(len) -> \(n) (offset now \(offset)/\(data.count))")
        return n
    }

    override func getBuffer(
        _ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
        length: UnsafeMutablePointer<Int>
    ) -> Bool { false }
}
```

Drive it with a plain `URLSessionDataDelegate` implementing `needNewBodyStream`/`didSendBodyData`/`didReceive response:`/`didReceive data:`/`didCompleteWithError:`, `session.uploadTask(withStreamedRequest:)`, `task.resume()`. **Expected result on the buggy OS build: `read()` logs exactly once, `didSendBodyData` fires once with the full byte count, then nothing until `didCompleteWithError` with `NSURLErrorTimedOut`.**

### 6.4 Known-good positive control

Same delegate/task setup as §6.3, but `completionHandler(InputStream(data: payload))` instead of `MinimalInputStream`. **Expected: completes normally, `didReceive response:` fires with status 200, in well under a second.**

## 7. What to build

A **new, standalone SPM package**, outside `request-dl-nio`'s own dependency graph entirely — do not add it as a target/dependency of this repo's `Package.swift`. Suggested location: a sibling directory, e.g. `../urlsession-uploadstream-repro/` (adjust to wherever makes sense on the machine actually running this). Suggested name: `urlsession-uploadstream-repro`.

Requirements:

- [ ] **Zero dependencies beyond Foundation.** No SwiftNIO, no AsyncHTTPClient, no RequestDL. The whole point is isolating this to `URLSession`/CFNetwork itself — every extra dependency is another thing a skeptic could point at.
- [ ] A **Python HTTP/2 server** (§6.2, extend as needed) as the primary test receiver — deliberately not Swift/NIO-based, so a passing/failing result can never be blamed on `swift-nio-http2`.
- [ ] A **plain HTTP/1.1 Python server** too (chunked-decoding, per §4.1) for the HTTP/1.1 side of the matrix — cheap to keep both since the HTTP/1.1-vs-2 axis is already ruled out as *the* cause, but worth keeping as a control in case a fix behaves differently per version.
- [ ] A Swift test target (XCTest or swift-testing, either is fine) with, at minimum:
  - The positive control (§6.4) against both Python servers — must keep passing throughout the investigation as a canary that the harness itself isn't broken.
  - The minimal failing subclass (§6.3) against both Python servers — the baseline repro.
  - Room to add variants quickly — the harness should make it cheap to swap in a new `InputStream` subclass and rerun against both servers without rewriting the request/delegate/server-startup boilerplate each time.
- [ ] A short README in the new package pointing back at this file (`INPUT_STREAM_ANALISYS.md` in `request-dl-nio`) for context, so anyone opening the repro package cold can find the full backstory.

## 8. Concrete things to try next, roughly in priority order

Each is a single, cheap variant to swap into the §6.3 harness (or `urlsession-uploadstream-repro`'s equivalent) and rerun. Items 2, 8, and 9 (below) have been tried since this list was first written — see their entries and §4.8/§4.9/§4.10 — the rest have not.

1. **Real run-loop scheduling.** §6.3's `schedule(in:forMode:)`/`remove(from:forMode:)` are no-ops, matching every version tried so far (including RequestDL's real implementation, which explicitly reasoned that URLSession never schedules the stream on a run loop — that reasoning was never actually verified). Implement them for real (schedule/unschedule on the given run loop, fire `StreamDelegate` events through it) and see if that changes anything. **Partially answered by §4.8**: `schedule` *is* called (exactly once) for both `MinimalInputStream` and the §4.8 `CFReadStreamCreate`-backed variant, so the old assumption that URLSession never schedules the stream was wrong — but a no-op/counting-only callback still hangs, so scheduling *happening* isn't sufficient on its own. What's still untested: implementing it for real (actually registering with the run loop and firing `StreamDelegate`/`CFReadStreamSignalEvent` events through it) rather than just counting the call.
2. ~~**`getBuffer(_:length:)` returning `true`.**~~ **Tried — see §4.10.** Implemented for real on both a Swift subclass (`GetBufferInputStream`) and the §4.8 `CFReadStreamCreate`-backed stream (`CFCallbackStreamCreateWithGetBuffer`). Result: CFNetwork never calls `getBuffer` at all on either — `getBufferCallCount` stays 0, `read` is still called exactly once, and the hang is identical to declining it. This falsifies the hypothesis: there's no shortcut being taken or skipped, because it's never attempted regardless of whether it's offered.
3. **File-backed upload instead of a streamed `InputStream` at all.** `uploadTask(with:fromFile:)` is a completely different API shape — write the body to a temp file first, upload from there. This sidesteps the `InputStream` subclass question entirely. If this works reliably, it's a viable **workaround** for RequestDL even if the actual `InputStream` bug is never root-caused: buffer to a temp file instead of streaming through a custom `InputStream`. Worth testing early since it might make the rest of this investigation moot for RequestDL's practical purposes (though the underlying CFNetwork bug would still be worth reporting to Apple regardless).
4. **Explicit `Content-Length` instead of chunked/unknown-length.** `uploadTask(withStreamedRequest:)` is designed for unknown-length bodies, but try setting `request.setValue(String(payload.count), forHTTPHeaderField: "Content-Length")` explicitly before starting the task anyway — see if CFNetwork honors it and changes its end-of-body detection strategy as a result.
5. **Suppressing the draft negotiation.** Search `URLSessionConfiguration`/`URLSession` (headers, `Info.plist` keys, environment variables) for anything that opts out of `Upload-Draft-Interop-Version` — if the draft negotiation itself can be disabled, the whole bug class might be avoidable without needing to fix the `InputStream` interaction at all. Start with Apple's WWDC/release notes for whichever OS version first shipped this (likely a "one more thing" in a recent CFNetwork changelog) — if it can't be found, that's worth noting as "undocumented" rather than assuming it doesn't exist.
6. **A different OS/device.** If any other Mac (non-beta OS) or a physical iOS device is available, run the exact §6.3/§6.4 pair there. This is the cheapest way to find out whether this is a beta-OS regression (in which case: file feedback, wait, re-test on GA) or a long-standing bug (in which case: worth a permanent workaround regardless of OS version).
7. **Packet capture.** If none of the above resolves it, capture the actual TLS-decrypted traffic (e.g. via a local mitmproxy/Charles with the process's `SSLKEYLOGFILE` set, or Instruments' Network template) for both the passing (`InputStream(data:)`) and failing (`MinimalInputStream`) cases, and diff them at the frame level — there may be a wire-visible difference (a header, a frame type, timing) neither this investigation nor CFNetwork's public API surface has surfaced yet.
8. ~~**`CFReadStreamCreateWithCallbacks` instead of an `InputStream` subclass.**~~ **Tried — see §4.8.** Built and tested in `urlsession-uploadstream-repro` (`Sources/CFCallbackStream/` + `Sources/UploadStreamRepro/CFCallbackInputStream.swift`, tests `cfCallbackStreamHTTP1/HTTP2ReproducesHang`). Result: a genuine `CFReadStream` built via the private `CFReadStreamCreate` SPI hangs identically to a Swift `InputStream` subclass — this falsifies the theory that CFNetwork special-cases concrete `CFReadStream`-ness by object identity. §5's theory has been revised accordingly.
9. ~~**Reverse-engineer `copyProperty` via logging, then answer it.**~~ **Tried — see §4.9.** Implemented in `urlsession-uploadstream-repro` (`CFCallbackStream`'s `copyProperty`/`setProperty` callbacks now log every query, `cfCallbackStreamPropertyQueries(_:)` in Swift). Result: CFNetwork never calls `copyProperty` or `setProperty` at all before timing out — zero queries, for any property, over the stream's whole lifetime. This falsifies the "queryable length" hypothesis (§5, first revision) outright; there was nothing to answer. §5 has a second revision reflecting this and narrowing what's left untested to (a) `getBuffer` and (b) real run-loop/dispatch-queue scheduling — both still open, see items 1 and 2 above — plus (c) a possible `CFGetTypeID()`-level concrete-type check that no callback-level instrumentation can observe from inside the stream itself.

## 9. Done state

**Resolved via the first bullet below (2026-08-25).** Root cause (second bullet) was never fully nailed down -- see §5's last revision, still sitting on two untested leads (real run-loop event delivery, a `CFGetTypeID()`-level concrete-type check) -- but the workaround made that moot for RequestDL's purposes, so the investigation stopped there rather than chasing the root cause further. Kept here rather than deleted, so a future session doesn't have to redo everything in §4 if a real fix is ever worth pursuing (e.g. before filing feedback with Apple).

This investigation is "done" when one of:

- **A workaround is found** (most likely candidate: §8.3, file-backed upload) that lets RequestDL's real `Internals.URLSessionClient` complete a streamed upload reliably — bring it back to `request-dl-nio`, apply it to `Internals.URLSessionUploadStream`/`Internals.URLSessionClient`, and turn `RequestConfigurationURLSessionClientUploadTests`/`InternalsURLSessionClientSessionTaskTests`'s `withKnownIssue` wrappers into real, passing assertions. **Done**: `Internals.URLSessionUploadStream` (the `InputStream` subclass) is deleted outright, replaced by `Internals.URLSessionUploadFile` (`Sources/RequestDLInternals/.../URLSession Client/Upload/Internals.URLSessionUploadFile.swift`). Neither `uploadTask(with:from:)` nor `uploadTask(with:fromFile:)` goes through `InputStream`/`needNewBodyStream` at all, so neither is affected by this bug family, and both re-read the body themselves on any retry/redirect that resends it -- simpler than the old approach, which needed a fresh `InputStream` handed back per `needNewBodyStream` call. All four `withKnownIssue` wrappers this bug caused (`RequestConfigurationURLSessionClientUploadTests`'s two tests, `InternalsURLSessionClientSessionTaskTests`'s two `sessionTask_whenStreamingUpload...` tests) are now real, genuinely passing assertions -- confirmed by actually running them, not just removing the wrapper and assuming. New unit coverage for the replacement bridge itself: `InternalsURLSessionUploadFileTests` (`RequestDLInternalsTests`), mirroring the deleted `InternalsURLSessionUploadStreamTests`'s byte-for-byte/ordering discipline but for both branches below.

  **Refined same day, after review flagged the first cut as wasteful:** draining every streamed body to a temporary file unconditionally -- correct, but disk I/O for something that was already sitting in memory as `Data` a moment earlier, for the common case of an ordinary JSON/small payload upload. `Internals.URLSessionUploadFile.write(body:inMemoryThreshold:)` now drains up to `inMemoryThreshold` (8 MiB default) into memory first; a body that finishes within that returns `.data(Data)` and uploads via `uploadTask(with:from:)` with no disk I/O at all. Only a body that exceeds the threshold spills to a temporary file (what's already buffered, plus the remainder) and uploads via `uploadTask(with:fromFile:)`, exactly as the first cut always did. `Internals.URLSessionClient`'s two upload-driving call sites switch on this `Materialized` (`.data`/`.file`) result rather than assuming a file always exists.

  **Considered, initially deferred, then done the same day on request:** when the body is already backed by a single file on disk (`Payload(url:)`), the code above still drained it through the generic `AsyncSequence` path and re-copied it into a *new* temporary file -- doubling I/O for exactly the large-file-upload case where it matters most. Fixed by threading a "this buffer is already a file, here's its URL" signal up through the buffer abstraction after all: `Internals.Buffer.wholeFileURL` (`Stream == Internals.FileStreamBuffer` only) answers with the file's `URL` when unread (`readerIndex == .zero`) and not this package's own scratch file (`!isTemporary` -- required bumping `Internals.FileBufferURL.isTemporary` from `private` to `package`); `Internals.BodySequence.wholeFileURL`/`RequestBody.wholeFileURL` forward it only when the whole body is exactly that one buffer (not multipart, not `Data`-backed). `Internals.URLSessionUploadFile.Materialized` gained `.existingFile(URL)` (uploads the same way as `.file` via `uploadTask(with:fromFile:)`, but is never removed afterward -- not this package's file); `Internals.URLSessionClient+RequestExecutingClient.swift` passes `body.wholeFileURL` through as a new `existingUploadFile` parameter, `nil` (a no-op) whenever it doesn't qualify. New tests at every layer, including a real `Payload(url:)` round trip over `.urlSession` confirming the shortcut delivers exact bytes end to end, not just that the URL forwards correctly (`urlSessionClient_whenStreamingUploadFromExistingFile_deliversWholeBodyIntact`).

  One real behavior change worth knowing about, not hidden by the fix: a body large enough to spill to disk is fully written to a temporary file *before* the upload task starts (rather than streamed a slice at a time as `URLSession` requests it), and `Internals.FileBufferURL.temporaryURL`'s file briefly exists on disk for the duration of the request. `RequestConfiguration.buildURLRequest()`'s and this bridge's own doc comments were updated to say so plainly rather than still claiming "does not buffer `body` at all," which was true of the old, broken approach and is no longer true of the file-spillover branch specifically (the in-memory branch never touches disk at all).

- **A root cause is confirmed** precisely enough to write a minimal, standalone bug report Apple would actually accept via Feedback Assistant (the §6.3/§6.4 pair, packaged as an actual Xcode project since Feedback Assistant expects one, not a bare SPM `swift test` invocation) — file it, note the FB number here and in `URLSESSION_TASK.md`, and decide with the workaround question above whether RequestDL ships a workaround in the meantime or documents the limitation and waits. **Not done** — see the note at the top of this section. Worth doing later regardless of the workaround, since this is a real CFNetwork bug that will bite anyone else who tries a custom `InputStream` with `uploadTask(withStreamedRequest:)`; `urlsession-uploadstream-repro` (the standalone repro package this document asked for, §7/§9) already has everything a Feedback Assistant submission would need.
- **Neither is found** after exhausting §8 — in which case, write up what was tried and ruled out (this document's own §4 is the template) and bring the update back to `URLSESSION_TASK.md` Phase 7b4 as the new, final state of that known issue, explicitly more thorough than what existed before this document. Superseded by the first bullet above.

Either way, the result belongs back in `request-dl-nio`'s `URLSESSION_TASK.md` (Phase 7b4) and, if code changed, a PR against the `feature/urlsession-executor` branch (see that repo's git history/open PR for the current state of the URLSession executor work this all supports).
