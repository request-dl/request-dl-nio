# Suspend/resume: feasibility and internal design

Status: the internal mechanism (sections 1-3) landed with `suspend-resume-feasibility`, which
adds no public API. The public surface (section 4) is built on top of it in
`suspend-resume-public-api`: `RequestController` with `.controller(_:)`, and
`.resumingDownloads(_:)` with `DownloadResumptionPolicy`. User-facing documentation is the
DocC article "Suspending and resuming requests". Resumable uploads and cross-launch resume are
not built (section 4.5, and 4.3 respectively).

Branches: `suspend-resume-feasibility`, built on `urlsession-backpressure-redesign`
(`Internals.FlowControlWindow`, the `.nio` delegate back pressure and the `.urlSession`
`bytes(for:delegate:)` redesign); then `suspend-resume-public-api`, built on it.

---

## 1. What "suspend/resume" can mean

There are two structurally different capabilities hiding under the one name. They have
different mechanisms, different failure modes and very different feasibility, and they must
not be conflated in the eventual public API either.

### 1.1 In-flight pause (the connection stays open)

The app pauses a transfer that is in progress and later resumes it on the *same* exchange:
nothing is renegotiated with the server, and the bytes simply stop flowing for a while.

This is the back-pressure mechanism generalized from *incidental* (the reader is momentarily
slow, bounded by a watermark) to *deliberate* (the app said so, for as long as it says so).

**Downloads -- feasible on both executors, one mechanism.** Both producers already stop when
`Internals.FlowControlWindow` is not writable (`.nio`: `didReceiveBodyPart` returns a pending
future and AsyncHTTPClient stops reading the socket; `.urlSession`: the pump stops pulling
`URLSession.AsyncBytes` and CFNetwork stops reading once its own read-ahead is full). A
suspension flag on the window is therefore all a download needs, and it inherits every
existing release path (cancel, drop, reader gone, failure, finish) for free, which is what
keeps a long pause from ever turning into a hang.

- Granularity: `.nio` stops within one socket read of the suspension; `.urlSession` within
  CFNetwork's own read-ahead (measured at ~4.5 MiB by the back-pressure work) -- bytes already
  in flight still arrive.
- Suspension stops the *network*, not the reader: whatever is already buffered ahead of the
  reader (at most the window) keeps draining. That is deliberate -- withholding bytes that are
  already in memory would bound nothing -- and the public API should say so (progress can
  advance a little after "pause").

**Uploads -- feasible on both executors, but only by gating the body *producer*.**

- `.nio`: the request body is already pulled chunk by chunk by `Internals.StreamWriterSequence`
  and written through AsyncHTTPClient's `StreamWriter`; waiting before pulling the next chunk
  pauses the upload with one-chunk granularity.
- `.urlSession`: today's upload paths (`httpBody`, or `httpBodyStream` over Foundation's own
  file-backed `InputStream(url:)`) are pulled by CFNetwork itself -- there is no point at which
  RequestDL could say "not yet". The one public mechanism that gives RequestDL that point is a
  Foundation **bound stream pair** (`Stream.getBoundStreams`): CFNetwork reads the input end,
  RequestDL writes the output end, and simply not writing pauses the upload.
  Spike (`scratchpad`, re-run twice, 24 MiB body through `bytes(for:delegate:)`, both
  `Content-Length`-framed and chunked):
  - the end of the body *is* recognized (the CFNetwork end-of-body bug documented in
    `Internals.URLSessionUploadFile` only ever affected custom `InputStream` subclasses);
  - while the writer is paused, the server's received-byte count does not move at all
    (writer offset == server count, i.e. nothing in flight after the pair's buffer drains);
  - after resuming, the server receives the whole body, SHA-256 identical.
  `URLSessionTask.suspend()` was **not** used: it is exactly the OS-specific mechanism the
  product plan wants to avoid, it was already measured to lose its suspension under load on
  the download side, and with `bytes(for:delegate:)` the task handle isn't even available
  until the response head arrives -- i.e. after the upload.

**How long can a paused connection live?** Not forever, on either executor:

| Limit | `.nio` | `.urlSession` |
| --- | --- | --- |
| Client idle timeout, paused download | Only if `Timeout.read` is configured: AsyncHTTPClient's idle-read timer is reset per read and not paused by back pressure, so a pause longer than `read` fails with `readTimeout`. RequestDL sets none by default. | `timeoutIntervalForRequest` (default 60 s) fires while nothing arrives; surfaces as `URLError.timedOut` (measured by the back-pressure work). |
| Client idle timeout, paused upload | None: AsyncHTTPClient's idle-read timer only starts once the request end is sent, and RequestDL never sets its idle-write timeout. | `timeoutIntervalForRequest` also applies: measured, a 4 s upload pause with a 1.5 s timeout failed with `-1001` after 1.61 s, server saw a truncated body. |
| Resource deadline | `Timeout.resource` (`Internals.ResourceDeadline`) keeps running during a pause on both executors. | same |
| Server / middleboxes | Out of RequestDL's control: e.g. nginx `send_timeout`/`client_body_timeout` (60 s default), load-balancer idle timeouts (typically 60 s). | same |
| TCP | A zero-window connection stays up indefinitely (persist timer); not a limit in practice. | same |

**Conclusion for 1.1:** in-flight pause is a *best-effort, bounded-duration* capability. It is
acceptable -- and matches today's behaviour -- for a pause that outlives the connection to
fail, *provided it fails promptly and visibly rather than hanging*. For downloads, such a
failure is exactly where 1.2 takes over; for uploads it stays a failure.

### 1.2 Resume after the connection is gone

The connection dropped (network change, server/middlebox idle timeout during a long pause,
app suspended by the OS...), and the transfer has to continue on a *new* exchange.

**Downloads -- feasible, executor-agnostic logic, via HTTP `Range` + `If-Range`.**
Re-issue the original request with `Range: bytes=N-` and `If-Range: <validator>`, where `N`
is the number of representation bytes already delivered, and splice the `206` continuation
into the same body stream. Preconditions (anything else is not resumable and fails exactly as
today):

- method `GET`, and the original request carried no `Range` of its own;
- original response `200`;
- a **strong validator**: a strong `ETag`, or -- only when there is no `ETag` -- a
  `Last-Modified` that is strong per RFC 9110 §8.8.2.2 (the response's `Date` at least one
  second later). `If-Range` must never carry a weak validator (RFC 9110 §13.1.5); without a
  strong validator a change of the resource cannot be detected, and bytes of two different
  versions could be spliced together;
- no content coding (`Content-Encoding` absent or `identity`). This is conservative: when a
  transport decodes natively (CFNetwork, `NIOHTTPResponseDecompressor`), delivered bytes are
  decoded bytes and `N` would not be a representation offset. (Manually dispatched decoding
  does count raw bytes and could be allowed later with care; not needed now.)

Validation of the continuation, all of which must hold, or the download fails with
`Internals.DownloadResumptionMismatchError` *without splicing a single byte*:

- status `206` with `Content-Range: bytes N-…/L`, start exactly `N`, `L` equal to the
  original `Content-Length` when that was known;
- the `206`'s `ETag`, when present, equal to the original;
- a `200` means the validator no longer matches (the resource changed) or the server ignores
  `Range`: either way the new body can't be spliced, so it fails;
- `416` with `Content-Range: bytes */L` and `L == N` means everything had already arrived
  (typically a chunked body whose terminator was lost): the download ends successfully.

"Connection gone" is an executor-specific classification of transport errors (connection
lost/reset/closed, idle timeouts, connect failures on the retry); cancellation, TLS/trust,
redirect-policy, protocol and decoding errors never qualify. Attempts are bounded
(consecutive attempts without progress) with a delay between them. A drop *while suspended*
does not reconnect until the app resumes: reconnecting only for the new connection to idle out
again would be pointless.

**Relaunch / termination.** The internal mechanism resumes within the process. Resuming
across an app relaunch additionally needs (a) the already-received bytes persisted somewhere
the app controls and (b) the resume point (URL, validator, offset, length) persisted with them.
Both are public-API/product decisions (where does a `DataTask`'s partial body live? only
`DownloadTask`-to-file?). `Internals.RangeResumptionPlan` is a plain value type so the public
layer can persist it and start a fresh exchange from an offset with the same validation.

**Uploads -- no universal mechanism; out of scope pending a product decision.**
There is no standard way to ask an arbitrary server how much of a `PUT`/`POST` body it
received. Re-sending the whole body is not resumption and must not be presented as such.
Genuine upload resumption requires a server-side protocol:

- **IETF resumable uploads** (`draft-ietf-httpbis-resumable-upload`): the upload resource is
  announced in a `104 Upload Resumption Supported` interim response, the offset recovered with
  `HEAD`, and the rest appended with `PATCH` (`Upload-Offset`, `Upload-Complete`). Neither
  transport surfaces interim responses: AsyncHTTPClient ignores every `1xx` except `101`
  (`HTTPRequestStateMachine`, "We ignore any leading 1xx headers"), and `URLSession` exposes
  none (it consumes them only inside its own OS-version-specific `uploadTask` auto-resume,
  which `bytes(for:delegate:)` has no counterpart for -- see the previous commit). A client
  implementation would therefore need a creation step that doesn't depend on `104`, which the
  draft's later revisions allow but which then requires the app to opt in per request.
- **tus 1.0**, and vendor protocols (GCS resumable uploads, S3 multipart): each is its own
  client state machine and its own server contract.

Recommendation: treat resumable uploads as a separate feature built around an explicit,
app-selected protocol (e.g. an internal `ResumableUploadProtocol` with one implementation per
supported server contract), not an auto-negotiated behaviour. Which protocol(s) to support is
the product decision that has to come first. Nothing in this branch guesses at it.

### 1.3 Scope of this branch

Built (internal, `package` visibility, opt-in, zero behaviour change when not opted in):

1. In-flight suspend/resume for **downloads and uploads**, on **both** executors, through one
   primitive (`Internals.FlowControlWindow` suspension, coordinated by
   `Internals.TransferControl`).
2. `Range`/`If-Range` **download reconnection** after the connection is gone, on both
   executors, sharing one executor-agnostic plan/validation type.

Deferred: upload reconnection (product decision above) and cross-launch persistence. The
public API is `suspend-resume-public-api` (section 4).

---

## 2. Internal design

See the doc comments on each type for the full invariants; this is the map.

- `Internals.FlowControlWindow` gains `suspend()`/`resume()`/`isSuspended`. Suspension is one
  more reason the window is not writable; `release()` still overrides everything, so every
  existing terminal path (cancel, drop, reader gone, failure, finish) still frees a producer
  parked by a suspension. `credit(_:)` never wakes a producer while suspended.
- `Internals.TransferControl` -- one per request execution:
  - `suspend()`/`resume()`/`isSuspended`, applied atomically to every participant;
  - `gate`: a never-charged `FlowControlWindow`, i.e. writable iff not suspended (or released).
    Upload producers wait on it between chunks, and download reconnection waits on it before
    reconnecting;
  - `attach(_:)`: each executor attaches the request's download window, which then follows
    the same suspension state;
  - `resumption`: the `Range` reconnection policy, `nil` (the default) meaning "fail on a drop
    exactly as before".
- Upload gating:
  - `.nio`: `Internals.StreamWriterSequence(writer:body:gate:)` waits on the gate before
    pulling each chunk. Reached from the real pipeline through
    `RequestConfiguration.build(eventLoop:uploadGate:)` -> `RequestBody.build(eventLoop:gate:)`.
  - `.urlSession`: `Internals.URLSessionUploadBodyPump`, only when a `TransferControl` is
    supplied: writes the (still materialized, exactly as before) body into a bound stream pair
    from a serial queue, driven by the output stream's own "can accept bytes" events, and stops
    writing while the gate is shut. `needNewBodyStream` (a 307/308 or auth retry) gets a fresh
    pair from offset 0. Without a `TransferControl`, `httpBody`/`httpBodyStream` are used as
    before.
- Download reconnection:
  - `Internals.RangeResumptionPlan` (pure, executor-agnostic): eligibility, request headers,
    continuation validation.
  - `Internals.DownloadResumptionState` (executor-agnostic value): plan, delivered-byte offset,
    attempt budget (consecutive attempts without progress).
  - `.urlSession`: `runExchange` -> `resumeDownload` loops over `bytes(for:delegate:)`
    exchanges into the same `DownloadBuffer`; the response pump now hands over bytes it had
    already pulled before rethrowing, so the offset is exactly what the reader got.
  - `.nio`: `Internals.ClientResponseReceiver` hands a resumable failure to
    `Internals.NIODownloadReconnection` instead of failing the body; continuations are received
    by `Internals.ResumedResponseReceiver`, which validates the `206` on the head (failing the
    head future on a mismatch, so not one byte is accepted) and appends into the same
    `DownloadBuffer`. A handed-over failure completes that exchange's own paused body-part
    future (`Internals.PausedBodyPart`) without releasing the shared window, so back pressure
    and suspension keep working across reconnections. Every ending of the body goes through
    `NIODownloadReconnection.terminate(_:)`, exactly once.
- Plumbing: `RequestExecutingClient.execute(configuration:decompression:cache:logger:transferControl:)`;
  `RawTask` passes `nil` today. The public API task only has to create a `TransferControl` per
  execution there and expose `suspend()`/`resume()`.

---

## 3. Measurements and verification

All against `TransferServer` (`Tests/RequestDLTestSupport/Transfer Server/`), a plain-socket
HTTP/1.1 server with 32 KiB socket buffers that counts body bytes the kernel accepted / received
and checks every byte against a position-dependent pattern. Every test body is parameterized over
both executors (`TransferExecutor`), so each guarantee is checked identically on `.nio` and
`.urlSession`. macOS 27, Debug build, loopback.

| Measurement | `.nio` | `.urlSession` |
| --- | --- | --- |
| Download: bytes the server got out after `suspend()` | ~0.3-0.5 MiB | ~2.2-4 MiB |
| Download: bytes in flight past the reader once stalled | ~0.5 MiB | ~4.5 MiB (CFNetwork read-ahead) |
| Download suspended before the response: bytes out | ~0.7 MiB | ~4.9 MiB |
| Download held suspended for 2 s | server count and reader both flat, window has 1 waiter, 1 connection | same |
| Upload: bytes the server received after `suspend()` (6 / 24 MiB) | ~0.7-1.0 MiB | ~0.7-1.0 MiB (kernel socket buffers; the bound pair itself drains to 0 -- measured 0 in the standalone spike) |
| Upload suspended before sending | 0 body bytes | 0 body bytes |
| Offset a continuation resumed at, connection cut at 5,000,000 | exactly 5,000,000 | 4,849,664 (fixed length) / 4,243,456 (chunked): CFNetwork drops what it had read ahead of `AsyncBytes` |
| Client idle timeout during a suspended download (1 s timeout, 3 s pause) | fails with `readTimeout` (only if `Timeout.read` configured) | fails with `URLError.timedOut` |
| Client idle timeout during a suspended upload (1 s, 3 s) | survives, body intact | fails with `URLError.timedOut` |

Verified behaviours (tests in `InternalsTransferControl{,Download,Upload,Stress}Tests`,
`InternalsRangeResumptionPlanTests`): resume after a hold delivers the whole body intact over the
same single connection; cancel/drop while suspended fails the reader, closes the connection and
releases window and gate; a connection lost while suspended without a resumption policy fails (no
hang); a lost connection continues with `Range`/`If-Range` (fixed length and chunked, strong
`ETag` and strong `Last-Modified`); a changed resource, a server ignoring `If-Range`, and a server
without range support are all rejected with `DownloadResumptionMismatchError` and not one byte of
the continuation reaches the reader; weak/absent validators never reconnect; a suspension
outliving the connection (server idle timeout *or* client idle timeout) reconnects on resume,
never while suspended; continuations without progress are given up after the budget; cancel
while waiting to reconnect never sends a continuation; uploads lost mid-body (or given up on by
the server during a suspension) fail exactly once and are never re-sent; a 307 resend on
`.urlSession` sends the whole body again through a fresh pair and stays suspendable; six
concurrent downloads (half of them losing their connection) plus six concurrent uploads, each
toggled suspend/resume every few milliseconds, all complete intact (run repeatedly).

### Findings along the way

- **`.nio` surfaces a connection cut mid-body as `HTTPParserError.invalidEOFState`**, not
  `HTTPClientError.remoteConnectionClosed` (that one is only for a close before the head). Any
  transient-failure classification for AsyncHTTPClient must include it.
- **Pre-existing CFNetwork behaviour, not fixed here:** a *chunked* response cut off exactly on
  a chunk boundary, without its terminating zero-length chunk, is reported by `URLSession` as a
  *successful, complete* response (bare `URLSession`, both `bytes(from:)` and `data(from:)`; a
  cut mid-chunk correctly fails with `-1005`). Such a truncation is invisible to RequestDL on
  `.urlSession`, so no reconnection can catch it. `.nio` reports it as `invalidEOFState`.
- `URLSession` loses the bytes CFNetwork read ahead of `AsyncBytes` when a connection fails;
  resumption counts only delivered bytes, so this costs re-downloading them, never corruption.

---

## 4. Public-API decisions

Decided in review, and implemented in `suspend-resume-public-api` except where noted below.
Where the earlier proposal changed, the change is noted.

### 4.1 Public surface: `RequestController`

```swift
let controller = RequestController()

try await DataTask { ... }
    .decode(...)
    .map { ... }
    .controller(controller)
```

- **Name: `RequestController`.** It controls (`suspend()`/`resume()`); it does not merely observe.
  `TransferControl` stays the internal name.
- **Wired through the environment**, like `.description(_:enabled:onDescribe:)`: it works anywhere
  in a task chain, does not change `Element`, and needs no change to `RequestTask`. `RawTask`
  reads it from `RequestEnvironmentValues`.
- **A shared switch, not one-per-execution.** One controller may be attached to several
  executions (for instance every child of a `GroupTask`); `suspend()` pauses all of them.
- **Sticky state.** Attaching to a suspended controller starts the execution suspended
  (measured: suspended before sending means zero body bytes on the wire).
- `suspend()`/`resume()` are synchronous, non-throwing, idempotent, `Sendable`, and do nothing
  on an execution that has finished.
- **Cancellation is not on the controller.** Swift `Task` cancellation stays the mechanism; it
  already releases the window and the gate.
- The controller owns the internal `TransferControl` of each execution. A `TransferControl` is
  only created when a controller (or an opted-in resumption) is attached, so the `.urlSession`
  upload path keeps today's behaviour, not the bound-pair path, for everyone else.

### 4.2 Range reconnection: opt-in

Changed from the earlier proposal ("on by default"). Download managers (browsers, `wget`,
Android `DownloadManager`) resume on their own, but HTTP client libraries (`URLSession`,
Alamofire, OkHttp) leave it to the app. A silent reconnect would also change behaviour for every
existing `DownloadTask`, which today fails when the connection drops mid-body. So: opt-in in the
first release, default reconsidered later. When enabled:

- only `GET`, only against a strong `ETag` or strong `Last-Modified` (RFC 9110 §13.1.5);
- a finite budget of attempts without progress;
- a changed resource, a server ignoring `If-Range`, or no range support is rejected before any
  byte of the continuation reaches the reader.

`.disabled` remains available.

Implemented as the task modifier `.resumingDownloads(_ policy: DownloadResumptionPolicy = .enabled())`,
with `DownloadResumptionPolicy.enabled(maximumAttemptsWithoutProgress:delay:)` and `.disabled`. It
travels through the environment like `.controller(_:)`, and the modifier closest to the task wins.
Asking for resumption alone creates a `TransferControl` that cannot be suspended
(`allowsSuspension: false`), so it never changes how a request body is sent.

### 4.3 Partial bodies

- In-process resumption needs only the delivered-byte count and the validator, both already
  tracked; it adds no storage. A `DataTask` keeps accumulating in memory, as today.
- **No spill-to-disk for `DataTask`:** its result is a `Data`, so moving the body to disk would
  only move the memory cost to `result()`. Very large bodies belong to `DownloadTask`.
- A size limit that *fails* with a clear error (for example `maxBodySize`) is a separate feature
  and not part of this work.
- Cross-launch resume: `DownloadTask` to a file only.

### 4.4 Pause duration versus timeouts

Document, don't mask: a suspended download that outlives the connection reconnects on resume
(when reconnection is enabled); a suspended `.urlSession` upload fails with `URLError.timedOut`.

### 4.5 Resumable uploads: separate branch

Out of this work. The plan for it: implement the IETF `resumable-upload` draft **once, above the
executors**, so `.urlSession` and `.nio` behave identically (`URLSession`'s own implementation
only exists on `uploadTask`, which `bytes(for:delegate:)` has no counterpart for). It needs the
creation step that does not depend on the `104` interim response, so it is opt-in per request,
never auto-negotiated. The extension point is an upload-strategy protocol, **not** a delegate on
`RequestController`; it stays internal until a second implementation (likely tus) exists to shape
it. Before starting, verify the draft's current status and which servers support it.
