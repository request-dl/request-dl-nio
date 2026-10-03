//
// See LICENSE for this package's licensing information.
//

// Covers a single non-streaming request/response round trip (`Data` in, `Data` out), redirect
// enforcement, `.server` proxy support, disabling URLSession's own cookie jar, TLS/mTLS challenge
// handling, streamed request-body uploads, and streamed response-body downloads.

#if canImport(Darwin)

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    /// The `URLSession`-backed executor. Apple platforms only, hence the file-wide
    /// `canImport(Darwin)` gate.
    package final class URLSessionClient: @unchecked Sendable {

        // MARK: - Internal properties

        /// Whether this client currently has any request in flight. Mirrors
        /// `Internals.Client.isRunning`, read by `Internals.ClientManager`'s idle-cleanup sweep so
        /// a busy client is never recycled out from under an in-flight request.
        package var isRunning: Bool {
            operationQueue.isRunning
        }

        /// Mirrors `Internals.ClientOperationQueue.generation`, read by
        /// `Internals.ClientManager`'s idle-cleanup sweep and ceiling eviction alongside
        /// `isRunning` -- see that property's own doc comment.
        package var operationGeneration: UInt64 {
            operationQueue.generation
        }

        // MARK: - Private properties

        private let session: URLSession
        private let throttledExecutor: Internals.ThrottledExecutor
        /// Transport-agnostic in-flight counter also used by `Internals.Client`. Backs
        /// `isRunning` the same way there, just for `URLSession` tasks instead of
        /// `HTTPClient.Task`s.
        private let operationQueue = Internals.ClientOperationQueue()
        private let redirectConfiguration: Internals.RedirectConfiguration
        private let proxyAuthorization: Internals.Proxy.Authorization?
        private let identityPolicy: Internals.URLSessionIdentityPolicy?
        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _isClosed = false

        // MARK: - Inits

        /// - Parameter secureConnection: Resolved once, here, into an
        /// `Internals.URLSessionIdentityPolicy`, including the Keychain round-trip a client
        /// identity needs, and cached for the lifetime of this client, mirroring
        /// NIOSSL's own per-connection `TLSConfiguration` caching in `Internals.ClientManager`.
        /// `nil` when the resolved request carries no TLS customization at all.
        /// - Parameter redirectConfiguration: Defaults to AsyncHTTPClient's own default
        /// (`.follow(max: 5, allowCycles: false)`, see `HTTPClient.Configuration.RedirectConfiguration.init()`)
        /// so a caller that does not set `Internals.Session.Configuration.redirectConfiguration`
        /// gets identical behavior regardless of which executor the session resolves to.
        /// - Parameter proxy: Both `.http` (`.server`) and `.socks` are mapped onto
        /// `configuration`. `.bearer` proxy authorization is the one thing that stays excluded
        /// from `.urlSession` upstream (`Internals.ExecutorIncompatibilityReason
        /// .proxyBearerAuthorizationUnderURLSession`), so a well-formed caller never passes that
        /// here. See `Internals.Proxy.buildConnectionProxyDictionary()`'s doc comment for the
        /// per-platform status of this mapping.
        package init(
            configuration: URLSessionConfiguration,
            secureConnection: Internals.SecureConnection? = nil,
            redirectConfiguration: Internals.RedirectConfiguration = .follow(max: 5, allowCycles: false),
            proxy: Internals.Proxy? = nil,
            maximumConcurrentConnections: Int? = nil
        ) throws {
            let configuration = configuration
            // Explicitly `[:]`, not left untouched, when `proxy` is `nil`. `URLSession` treats an
            // unset `connectionProxyDictionary` as "inherit whatever macOS's Network preferences
            // (or a device's Wi-Fi proxy config) currently say," unlike AsyncHTTPClient, which has
            // no such discovery at all.
            //
            // Without this, a caller who declares neither `Proxy` nor `SystemProxy` (the
            // documented "system proxy is ignored unless opted into" contract `SystemProxy`'s own
            // doc comment makes) would silently pick up an ambient proxy anyway on `.urlSession`,
            // but not on the NIO executor: the exact kind of executor-dependent behavior change
            // this package works hard to avoid elsewhere (see `httpShouldSetCookies`/
            // `httpCookieStorage` below, same rationale).
            configuration.connectionProxyDictionary = proxy?.buildConnectionProxyDictionary() ?? [:]

            // Required normalization, not optional: URLSession persists cookies in a jar by
            // default, the NIO executor has none at all. Without
            // this, which executor a session happens to resolve to would silently change
            // behavior across requests that share a session.
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil

            session = URLSession(configuration: configuration)
            throttledExecutor = Internals.ThrottledExecutor(
                maximumConcurrentConnections: maximumConcurrentConnections
            )
            self.redirectConfiguration = redirectConfiguration
            self.proxyAuthorization = proxy?.authorization
            self.identityPolicy = try secureConnection.map(Internals.URLSessionIdentityPolicy.init)
        }

        // MARK: - Internal methods

        /// Executes `request`, buffering the whole response body into memory.
        ///
        /// - Parameter delegate: Per-task delegate for concerns this method does not itself
        /// handle. `nil` falls back to the session's own default handling. Redirect enforcement,
        /// proxy authentication, and, when this client was built with a `secureConnection`,
        /// the server-trust/client-certificate challenge (see `TaskDelegate` below) all run
        /// regardless of `delegate`; `delegate` is only consulted for a TLS challenge this client
        /// has no `identityPolicy` to answer.
        ///
        /// Deliberately not `session.data(for:request:delegate:)`. A captured crash report
        /// (`EXC_BREAKPOINT`/`SIGTRAP`, entirely inside Foundation's own
        /// `NSURLSession.data(for:delegate:)` closures on the `com.apple.NSURLSession-work`
        /// queue, no frame of this package's own code anywhere in the crashing thread) confirms a
        /// real, if rare, bug in that bridge, reproducible on an iOS Simulator under heavy
        /// concurrent test load, not this package's own delegate (`TaskDelegate`'s shared state
        /// is already lock-protected).
        ///
        /// Bridged by hand instead, the same way the streamed-upload
        /// overload below already does: build a plain `dataTask(with:)` with no completion
        /// handler of its own, so `TaskDelegate` (already `URLSessionDataDelegate`-conforming) is
        /// the *only* thing consuming the response/data, and let its own
        /// `didCompleteWithError:`, which already knows how to turn `redirectError`/the
        /// accumulated response into exactly this method's return shape, resolve `completion`
        /// once the task finishes. (An earlier version of this fix instead read `data`/`response`
        /// off a `dataTask(with:completionHandler:)` completion handler directly, alongside the
        /// same delegate: reachable together, but not guaranteed to agree with each other.
        /// Caught by `execute_whenRedirectChainExceedsMax_throwsRedirectLimitReachedError`, which
        /// started failing with `MissingURLResponseError` instead of the expected
        /// `RedirectLimitReachedError` once a redirect was actually refused.)
        ///
        /// `session.data(for:delegate:)` also cancelled its underlying `URLSessionTask`
        /// automatically when the awaiting Swift `Task` was cancelled: a guarantee this hand
        /// bridge has to restore explicitly, via `CancellableTaskBox`, since nothing does that for
        /// a bare `withCheckedThrowingContinuation` on its own.
        package func execute(
            request: URLRequest,
            delegate: URLSessionTaskDelegate? = nil
        ) async throws -> (head: Internals.ResponseHead, body: Data) {
            // Registered before the throttle wait below, not after: `Internals.ClientManager`'s
            // idle-cleanup sweep and its ceiling eviction path both treat `isRunning == false` as
            // "safe to shut down," and this client has no ARC-based fallback the way `.nio`'s
            // pooled entry does (its `shutdown()` invalidates the live `URLSession` outright). A
            // caller queued behind `throttledExecutor.acquire()` for longer than the pool's
            // lifetime must still count as busy, or the sweep can invalidate the session out from
            // under it the moment it's finally let through.
            let operation = operationQueue.operation()
            defer { operation.complete() }

            // Waited on before anything else, mirroring `Internals.Client.execute`: a session
            // configured with a limit must never let more requests than that reach the network,
            // whether the cap is enforced by the NIO or the URLSession executor.
            let release = await throttledExecutor.acquire()
            defer { release() }

            // `AsyncSemaphore.wait()` (backing `acquire()` above) is documented as "cancellation
            // transparent": a waiter cancelled while queued still takes its turn once a slot
            // frees up, rather than being skipped. Without this check, a caller whose own `Task`
            // was cancelled while queued here still had its request dispatched onto the wire the
            // moment `acquire()` returned.
            try Task.checkCancellation()

            let tlsDelegate = identityPolicy.flatMap { policy in
                request.url?.host.map { TLSDelegate(host: $0, policy: policy) }
            }

            let taskDelegate = TaskDelegate(
                redirectConfiguration: redirectConfiguration,
                initialRequest: request,
                proxyAuthorization: proxyAuthorization,
                tls: tlsDelegate,
                forwarding: delegate
            )

            let box = CancellableTaskBox()

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    taskDelegate.completion = { continuation.resume(with: $0) }

                    let task = session.dataTask(with: request)
                    task.delegate = taskDelegate
                    box.task = task
                    task.resume()
                }
            } onCancel: {
                box.cancel()
            }
        }

        /// Executes `request` with a body drained from `body` rather than buffered into `Data` up
        /// front. Materializes `body` (any `AsyncSequence` of `Internals.Bytes`; in practice
        /// `Internals.BodySequence`, or `RequestBody.bytesSequence` from the `RequestDL` module,
        /// both of which conform) via `Internals.URLSessionUploadFile`, then uploads from
        /// whichever shape that produced: `uploadTask(with:from:)` for a body small enough to
        /// just hold in memory, `uploadTask(with:fromFile:)` for one that spilled to disk.
        ///
        /// Deliberately does not drive `uploadTask(withStreamedRequest:)` + `needNewBodyStream`
        /// via a custom `InputStream`: that path has a confirmed CFNetwork bug where no custom
        /// `InputStream` (Swift subclass or a genuine `CFReadStream`) is ever recognized as
        /// reaching end-of-body. Neither of the two shapes used here goes through `InputStream` at
        /// all, so neither is affected; the file-backed one also re-reads the file itself for any
        /// retry/redirect that resends the body, so nothing here needs to hand back a fresh body
        /// more than once.
        ///
        /// - Parameter existingUploadFile: Set when the caller already knows `body`'s entire
        /// content is sitting untouched in this file (`RequestBody.wholeFileURL`, a
        /// `Payload(url:)`-only body). Skips `Internals.URLSessionUploadFile.write(body:)`
        /// entirely rather than draining `body` only to recreate a copy of a file that already
        /// exists. `body` is still required in that case (for the generic `Body` type/call-site
        /// symmetry with the other overload below) but is never iterated.
        /// - Parameter onUploadProgress: Called once per `didSendBodyData` callback, in delivery
        /// order, with `(bytesSentThisCall, totalBytesExpectedToSend)`. Order and eventual
        /// completion are what's guaranteed; individual chunk sizes are URLSession's own to
        /// pick, not RequestDL's.
        package func execute<Body: AsyncSequence & Sendable>(
            request: URLRequest,
            streaming body: Body,
            delegate: URLSessionTaskDelegate? = nil,
            existingUploadFile: URL? = nil,
            onUploadProgress: (@Sendable (Int, Int) -> Void)? = nil
        ) async throws -> (head: Internals.ResponseHead, body: Data) where Body.Element == Internals.Bytes {
            // See the equivalent comment in `execute(request:delegate:)`: registered before the
            // throttle wait so this client counts as busy for as long as a caller is queued on
            // it, not just once it starts sending.
            let operation = operationQueue.operation()
            defer { operation.complete() }

            let release = await throttledExecutor.acquire()
            defer { release() }

            // See the equivalent comment in `execute(request:delegate:)`: a cancelled caller
            // must not have its request dispatched once a slot frees up, since the semaphore
            // itself is "cancellation transparent" and would otherwise let it through anyway.
            try Task.checkCancellation()

            let materialized: Internals.URLSessionUploadFile.Materialized
            if let existingUploadFile {
                materialized = .existingFile(existingUploadFile)
            } else {
                materialized = try await Internals.URLSessionUploadFile.write(body: body)
            }

            let tlsDelegate = identityPolicy.flatMap { policy in
                request.url?.host.map { TLSDelegate(host: $0, policy: policy) }
            }

            let taskDelegate = TaskDelegate(
                redirectConfiguration: redirectConfiguration,
                initialRequest: request,
                proxyAuthorization: proxyAuthorization,
                tls: tlsDelegate,
                forwarding: delegate,
                onUploadProgress: onUploadProgress
            )

            let box = CancellableTaskBox()

            do {
                // Mirrors `execute(request:delegate:)`'s `CancellableTaskBox` use: without it, a
                // caller's `Task` cancellation while this continuation is suspended would never
                // reach the underlying `URLSessionTask`, leaving the upload running unnoticed.
                let result = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        taskDelegate.completion = { continuation.resume(with: $0) }

                        let task: URLSessionTask
                        switch materialized {
                        case .data(let data):
                            task = session.uploadTask(with: request, from: data)
                        case .file(let bufferURL):
                            task = session.uploadTask(with: request, fromFile: bufferURL.absoluteURL())
                        case .existingFile(let url):
                            task = session.uploadTask(with: request, fromFile: url)
                        }

                        task.delegate = taskDelegate
                        box.task = task
                        task.resume()
                    }
                } onCancel: {
                    box.cancel()
                }

                if case .file(let bufferURL) = materialized {
                    await bufferURL.removeIfTemporary()
                }
                return result
            } catch {
                if case .file(let bufferURL) = materialized {
                    await bufferURL.removeIfTemporary()
                }
                throw error
            }
        }

        /// Executes `request`, returning as soon as the response head arrives rather than
        /// waiting for the whole body. Mirrors the NIO backend's own
        /// `Internals.AsyncResponse` shape: `Internals.DownloadStep.bytes` is a live
        /// `Internals.AsyncBytes` a caller iterates separately, re-chunked to `readingMode` by
        /// `Internals.DownloadBuffer`, the same type `Internals.Session.execute(...)` builds for
        /// the NIO path, reused verbatim here rather than reimplemented, since it already has no
        /// NIO dependency of its own (it consumes `Internals.AnyBuffer`, not `ByteBuffer`
        /// directly).
        ///
        /// Unlike the other two `execute` overloads, the throttle slot acquired at the top is
        /// *not* released when this method returns: it has to stay held until the download
        /// itself finishes, which happens well after this `async` call returns its
        /// `Internals.DownloadStep`. `TaskDelegate` releases it from
        /// `urlSession(_:task:didCompleteWithError:)` instead.
        package func execute(
            request: URLRequest,
            readingMode: Internals.DownloadStep.ReadingMode,
            delegate: URLSessionTaskDelegate? = nil
        ) async throws -> Internals.DownloadStep {
            // See the equivalent comment in `execute(request:delegate:)`: registered before the
            // throttle wait so this client counts as busy for as long as a caller is queued on
            // it, not just once it starts sending.
            let operation = operationQueue.operation()
            let release = await throttledExecutor.acquire()

            // See the equivalent comment in `execute(request:delegate:)`: a cancelled caller
            // must not have its request dispatched once a slot frees up. Both the operation slot
            // and the throttle permit are handed back here, since neither overload's usual
            // release path (`onDownloadComplete`, wired up below) ever runs when the request is
            // never actually dispatched.
            guard !Task.isCancelled else {
                release()
                operation.complete()
                throw CancellationError()
            }

            let tlsDelegate = identityPolicy.flatMap { policy in
                request.url?.host.map { TLSDelegate(host: $0, policy: policy) }
            }

            // Built here, in an `async` context that can freely `await`, rather than inside a
            // synchronous delegate callback: `Internals.DownloadBuffer.init(readingMode:)` is
            // itself `async`, and `didReceive response:completionHandler:` below has no way to
            // await it without risking `didReceive data:` firing (URLSession serializes delegate
            // callbacks for one task, but only across calls that have themselves returned) before
            // a detached `Task` doing so had a chance to finish.
            let downloadBuffer = await Internals.DownloadBuffer(readingMode: readingMode)

            let taskDelegate = TaskDelegate(
                redirectConfiguration: redirectConfiguration,
                initialRequest: request,
                proxyAuthorization: proxyAuthorization,
                tls: tlsDelegate,
                forwarding: delegate,
                downloadBuffer: downloadBuffer,
                onDownloadComplete: {
                    release()
                    operation.complete()
                }
            )

            let box = CancellableTaskBox()

            // Same reasoning as `execute(request:delegate:)`: a bare continuation has no
            // cancellation handling of its own, so without this, cancelling the calling `Task`
            // while it's suspended here would leave the `URLSessionTask` (and the throttle slot
            // held above, only released from `onDownloadComplete`) running unnoticed.
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    taskDelegate.headCompletion = { continuation.resume(with: $0) }

                    let task = session.dataTask(with: request)
                    task.delegate = taskDelegate
                    box.task = task
                    task.resume()
                }
            } onCancel: {
                box.cancel()
            }
        }

        /// Executes `request`, returning a `SessionTask` whose response streams upload progress
        /// (when `request` carries a body), the response head, and the body, optionally teed
        /// to `cache` as it downloads.
        ///
        /// Mirrors `Internals.Client.execute(request:url:readingMode:uploadingBytes:cache:logger:)`:
        /// gives `RequestExecutingClient`'s `.urlSession` conformance the same three
        /// independent `Internals.AsyncStream`s (`upload`/`head`/`download`) to build an
        /// `Internals.AsyncResponse` from that the NIO backend already produces, just fed by this
        /// client's own callbacks instead of `Internals.ClientResponseReceiver`'s.
        ///
        /// Unlike every other overload here, the response body is read through
        /// `URLSession.bytes(for:delegate:)` rather than `TaskDelegate`'s `didReceive data:`, so a
        /// reader slower than the network holds the connection back instead of the body piling up
        /// in memory. See `executeSessionTask` for how, and why this is the only mechanism that
        /// does so reliably.
        ///
        /// - Parameter flowControl: How far ahead of the reader the body may get before the
        ///   response stops being read. The `.urlSession` counterpart to the parameter of the same
        ///   name on `Internals.Client.execute(request:url:readingMode:...)`: a fresh window with
        ///   the default watermarks per request; only tests pass their own.
        /// - Parameter transferControl: Suspends and resumes this execution, and reconnects its
        ///   download if the connection is lost (see `Internals.TransferControl`). `nil` behaves
        ///   exactly as before it existed.
        package func execute(
            request: URLRequest,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            delegate: URLSessionTaskDelegate? = nil,
            flowControl: Internals.FlowControlWindow = .init(),
            transferControl: Internals.TransferControl? = nil
        ) async throws -> SessionTask {
            try await executeSessionTask(
                request: request,
                readingMode: readingMode,
                uploadingBytes: uploadingBytes,
                decompression: decompression,
                cache: cache,
                logger: logger,
                forwarding: delegate,
                flowControl: flowControl,
                transferControl: transferControl,
                makeUploadBody: nil
            )
        }

        /// Combines what `execute(request:streaming:delegate:onUploadProgress:)` and
        /// `execute(request:readingMode:delegate:)` each build separately: a request body
        /// materialized the same way the former does, *and* a genuinely streamed, flow-controlled
        /// response, at once. See the bodyless `SessionTask` overload just above and
        /// `executeSessionTask` for everything else (the three-stream
        /// `SessionTask` shape, the cache tee, back pressure, and how the materialized body
        /// reaches the wire).
        /// - Parameter existingUploadFile: See the standalone streaming `execute`'s doc comment
        /// for this same parameter. Identical meaning here, `body` still required but unread
        /// when set.
        /// - Parameter flowControl: See the bodyless overload just above.
        /// - Parameter transferControl: See the bodyless overload just above. With one, the body
        ///   reaches the wire through `Internals.URLSessionUploadBodyPump`, which is what lets a
        ///   suspension pause the upload too.
        package func execute<Body: AsyncSequence & Sendable>(
            request: URLRequest,
            streaming body: Body,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            delegate: URLSessionTaskDelegate? = nil,
            existingUploadFile: URL? = nil,
            flowControl: Internals.FlowControlWindow = .init(),
            transferControl: Internals.TransferControl? = nil
        ) async throws -> SessionTask where Body.Element == Internals.Bytes {
            try await executeSessionTask(
                request: request,
                readingMode: readingMode,
                uploadingBytes: uploadingBytes,
                decompression: decompression,
                cache: cache,
                logger: logger,
                forwarding: delegate,
                flowControl: flowControl,
                transferControl: transferControl,
                makeUploadBody: {
                    if let existingUploadFile {
                        return .existingFile(existingUploadFile)
                    }
                    return try await Internals.URLSessionUploadFile.write(body: body)
                }
            )
        }

        /// Shared body for the two `SessionTask`-producing `execute` overloads above. They
        /// differ only in whether a body needs materializing first (`makeUploadBody`, `nil` for
        /// the no-body/non-streaming case).
        ///
        /// ## Why `bytes(for:delegate:)`
        ///
        /// Back pressure. The `didReceive data:` delegate the other overloads use has no way to
        /// say "not yet": CFNetwork keeps reading the socket and delivering whatever it read,
        /// regardless of how far behind the reader is, so a large or slowly-read body piles up in
        /// memory without bound. `URLSessionTask.suspend()` looks like the answer and is not:
        /// under ordinary CPU load (measured with the session's delegate queue held up for
        /// 200 ms), CFNetwork went on delivering the *entire* body to a task reporting
        /// `.suspended`, every time. `URLSession.AsyncBytes` is the one public mechanism that
        /// holds: Foundation feeds it through a data-delivery callback CFNetwork waits on before
        /// delivering more, so a reader that stops pulling stalls the connection itself, a few MiB
        /// past what it read, under the same load. See `pumpResponseBody` for how that is wired
        /// into `downloadBuffer`'s `Internals.FlowControlWindow`, and
        /// `InternalsURLSessionClientBackPressureTests` for the measurements this relies on.
        ///
        /// ## What `bytes(for:delegate:)` changes, and what it doesn't
        ///
        /// It owns the task, and only forwards *task*-level delegate callbacks to `TaskDelegate`
        /// (observed: redirects, authentication challenges, `didSendBodyData`,
        /// `needNewBodyStream`, metrics), never the data-level ones (`didReceive response:`,
        /// `didReceive data:`) or `didCompleteWithError:`, which it consumes itself. So:
        ///
        /// - Redirect enforcement, proxy authentication and TLS/mTLS challenges run through
        ///   `TaskDelegate` exactly as before. A refused redirect still surfaces its 3xx as the
        ///   response, and `redirectError` is checked against it the same way.
        /// - The response head comes back from `bytes(for:delegate:)` itself, and the end of the
        ///   exchange (success, failure, cancellation) from the body's `AsyncBytes` ending or
        ///   throwing, rather than from `didReceive response:`/`didCompleteWithError:`.
        /// - The request body can no longer go through `uploadTask(with:from:)`/
        ///   `uploadTask(with:fromFile:)`, which `bytes(for:delegate:)` has no counterpart for. The
        ///   body is still materialized exactly as before (`Internals.URLSessionUploadFile`), and
        ///   then attached to the request itself: see `attachUploadBody(_:to:)`, or, when the
        ///   execution can be suspended, `Internals.URLSessionUploadBodyPump`.
        ///
        /// ## Suspension and reconnection
        ///
        /// With a `transferControl`, `flowControl` follows its suspension (the pump parks on it
        /// like it parks behind a slow reader), the request body is written through a pump that
        /// waits on its gate, and a download whose connection is lost can continue on a new
        /// exchange (see `runExchange` and `Internals.RangeResumptionPlan`).
        private func executeSessionTask(
            request: URLRequest,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            forwarding delegate: URLSessionTaskDelegate?,
            flowControl: Internals.FlowControlWindow,
            transferControl: Internals.TransferControl?,
            makeUploadBody: (@Sendable () async throws -> Internals.URLSessionUploadFile.Materialized)?
        ) async throws -> SessionTask {
            // Before anything can be produced into the window, so a suspension that came first
            // already holds.
            transferControl?.attach(flowControl)

            // See the equivalent comment in `execute(request:delegate:)`: registered before the
            // throttle wait so this client counts as busy for as long as a caller is queued on
            // it, not just once it starts sending.
            let operation = operationQueue.operation()
            let release = await throttledExecutor.acquire()

            // See the equivalent comment in `execute(request:delegate:)`: a cancelled caller
            // must not have its request dispatched once a slot frees up. Both the operation slot
            // and the throttle permit are handed back here, since neither is tied to a `defer`
            // in this overload -- their usual release path (`onDownloadComplete`, wired up
            // below) never runs when the request is never actually dispatched.
            guard !Task.isCancelled else {
                release()
                operation.complete()
                throw CancellationError()
            }

            // CFNetwork's transparent `Content-Encoding` decoding can only be switched off by
            // taking over `Accept-Encoding` ourselves, and doing so suppresses it entirely, for
            // every encoding, not just the one added. So this is all-or-nothing: either every
            // configured algorithm is one CFNetwork already decodes natively and this stays
            // quiet, or `Accept-Encoding` is set here and this package decodes everything in the
            // list itself, manually, including the natives. `.disabled` reaches the same
            // `identity` override; see `Internals.Decompression.requiresManualURLSessionHandling`.
            let decompressionDispatch: Internals.ManualDecompressionDispatch
            var request = request

            switch decompression {
            case .disabled:
                // Only when the caller hasn't already set their own: `.disabled` means this
                // package leaves `Content-Encoding` handling alone entirely, and a caller who set
                // `Accept-Encoding` explicitly (e.g. `AcceptEncodingHeader`, documented as usable
                // exactly when the caller intends to decode the body itself) is relying on that
                // value reaching the wire unchanged, the same way it does under `.nio`. Without
                // this guard, `.urlSession` silently overwrote it with `identity` regardless,
                // defeating that configuration only under this executor.
                if request.value(forHTTPHeaderField: "Accept-Encoding") == nil {
                    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                }
                decompressionDispatch = .skip

            case .enabled(let algorithms, _) where decompression.requiresManualURLSessionHandling:
                request.setValue(
                    algorithms.map(\.contentEncodingValue).joined(separator: ", "),
                    forHTTPHeaderField: "Accept-Encoding"
                )
                decompressionDispatch = .dispatch(algorithms: algorithms)

            case .enabled:
                decompressionDispatch = .skip
            }

            let uploadBody: Internals.URLSessionUploadFile.Materialized?
            do {
                uploadBody = try await makeUploadBody?()
            } catch {
                release()
                operation.complete()
                throw error
            }

            let makeBodyStream: (@Sendable () -> InputStream?)?
            let uploadPump: Internals.URLSessionUploadBodyPump?
            do {
                if let uploadGate = transferControl?.uploadGate, let uploadBody {
                    let pump = try Internals.URLSessionUploadBodyPump(uploadBody, gate: uploadGate)
                    request.httpBodyStream = try pump.makeStream()
                    request.setValue(String(pump.size), forHTTPHeaderField: "Content-Length")
                    uploadPump = pump
                    makeBodyStream = { try? pump.makeStream() }
                } else {
                    uploadPump = nil

                    if let fileURL = try Self.attachUploadBody(uploadBody, to: &request) {
                        makeBodyStream = { InputStream(url: fileURL) }
                    } else {
                        makeBodyStream = nil
                    }
                }
            } catch {
                if case .file(let bufferURL) = uploadBody {
                    await bufferURL.removeIfTemporary()
                }
                release()
                operation.complete()
                throw error
            }

            let tlsDelegate = identityPolicy.flatMap { policy in
                request.url?.host.map { TLSDelegate(host: $0, policy: policy) }
            }

            let upload = Internals.AsyncStream<Int>()
            let head = Internals.AsyncStream<Internals.ResponseHead>()
            let downloadBuffer = await Internals.DownloadBuffer(
                readingMode: readingMode,
                flowControl: flowControl,
                observer: transferControl?.observer
            )
            let metrics = Internals.RequestMetricsCollector()

            let redirectConfiguration = redirectConfiguration
            let proxyAuthorization = proxyAuthorization

            let taskDelegate = TaskDelegate(
                redirectConfiguration: redirectConfiguration,
                initialRequest: request,
                proxyAuthorization: proxyAuthorization,
                tls: tlsDelegate,
                forwarding: delegate,
                onUploadProgress: { bytesSent, _ in
                    transferControl?.observer?.didSend(bytesSent)
                    upload.append(.success(bytesSent))
                },
                makeBodyStream: makeBodyStream,
                metrics: metrics
            )

            // A download continuation is a new exchange, so it gets a delegate of its own, with
            // its own redirect bookkeeping, for the same policies. It never has a body to send:
            // only a bodyless `GET` is ever resumed.
            let continuationDelegate: @Sendable (URLRequest) -> TaskDelegate = { continuation in
                TaskDelegate(
                    redirectConfiguration: redirectConfiguration,
                    initialRequest: continuation,
                    proxyAuthorization: proxyAuthorization,
                    tls: tlsDelegate,
                    forwarding: delegate,
                    metrics: metrics
                )
            }

            let box = CancellableTaskBox()
            let session = session
            let isResumable = uploadBody == nil

            // Unstructured on purpose: it runs for as long as the exchange does, well past this
            // method's return, the same way the `URLSessionTask` it replaces did. Owns every
            // ending: the throttle slot, the operation-queue slot and a spilled upload file are
            // released here, once, whichever way the exchange ends.
            let exchange = Task {
                await Self.runExchange(
                    session: session,
                    request: request,
                    taskDelegate: taskDelegate,
                    continuationDelegate: continuationDelegate,
                    box: box,
                    readingMode: readingMode,
                    cache: cache,
                    decompressionDispatch: decompressionDispatch,
                    upload: upload,
                    head: head,
                    downloadBuffer: downloadBuffer,
                    flowControl: flowControl,
                    transferControl: transferControl,
                    resumption: isResumable ? transferControl?.resumption : nil,
                    uploadPump: uploadPump
                )

                upload.close()
                release()
                operation.complete()

                // Only now, not once the body finished sending: a redirect or authentication
                // retry that resends it reopens this same file (`TaskDelegate`'s
                // `needNewBodyStream`) for as long as the exchange runs.
                if case .file(let bufferURL) = uploadBody {
                    await bufferURL.removeIfTemporary()
                }
            }

            let response = Internals.AsyncResponse(
                logger: logger,
                uploadingBytes: uploadingBytes,
                upload: upload,
                decompressionDispatch: decompressionDispatch,
                head: head,
                download: downloadBuffer.stream
            )

            // Cancelling or dropping the response cancels the exchange and releases the window,
            // mirroring `Internals.Client.execute(request:url:...)`.
            //
            // All three are needed. `box.cancel()` reaches the `URLSessionTask` once
            // `bytes(for:delegate:)` has handed it over; before that, only cancelling `exchange`
            // does, through `bytes(for:delegate:)`'s own cancellation handling (see
            // `runExchange`). Releasing the window wakes a pump parked on it, which then finds the
            // task cancelled on its next read instead of waiting for a reader that may never come.
            //
            // The same goes for a suspension: releasing the transfer control's gate wakes an
            // upload pump, or a download reconnection, parked on it.
            return SessionTask(
                seed: Internals.TaskSeed {
                    exchange.cancel()
                    box.cancel()
                    flowControl.release()
                    transferControl?.release()
                },
                response: response,
                metrics: metrics
            )
        }

        /// Runs one request for `executeSessionTask`, from sending it to the end of the response
        /// body, resolving `head` and ending `downloadBuffer` exactly once whichever way it goes --
        /// over as many exchanges as reconnecting a lost download takes, when `resumption` allows
        /// it.
        private static func runExchange(
            session: URLSession,
            request: URLRequest,
            taskDelegate: TaskDelegate,
            continuationDelegate: @Sendable (URLRequest) -> TaskDelegate,
            box: CancellableTaskBox,
            readingMode: Internals.DownloadStep.ReadingMode,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            decompressionDispatch: Internals.ManualDecompressionDispatch,
            upload: Internals.AsyncStream<Int>,
            head: Internals.AsyncStream<Internals.ResponseHead>,
            downloadBuffer: Internals.DownloadBuffer,
            flowControl: Internals.FlowControlWindow,
            transferControl: Internals.TransferControl?,
            resumption: Internals.DownloadResumptionPolicy?,
            uploadPump: Internals.URLSessionUploadBodyPump?
        ) async {
            // Nothing is produced into the window past this point, whichever way this ends, so
            // it must not be left able to pause anything. The pump stops before the gate opens,
            // so a pump parked on the gate wakes up to find itself already finished.
            defer {
                uploadPump?.stop()
                flowControl.release()
                transferControl?.release()
            }

            var isHeadResolved = false

            // The task of the exchange running now, so a failure lands on its own transaction:
            // `nil` between one task ending and the next one starting, and when `bytes(for:)`
            // throws before there is one.
            var currentTask: URLSessionTask?
            var isFailureRecorded = false

            do {
                // Ordinarily just one request. Loops only when `TaskDelegate` deferred a redirect
                // to here instead of handing it back to `URLSession` -- see
                // `completeRedirect(with:_:)`'s doc comment for why (a file-backed body resend
                // `URLSession` itself won't reliably carry out, observed directly on watchOS).
                // Each pass is a genuinely new task, sharing `taskDelegate` so redirect counting,
                // history and error state keep accumulating exactly as they would across
                // `URLSession`'s own automatic follows.
                func resolveExchange() async throws -> (URLSession.AsyncBytes, URLResponse) {
                    var currentRequest = request

                    while true {
                        currentTask = nil

                        let (bytes, response) = try await withTaskCancellationHandler {
                            try await session.bytes(for: currentRequest, delegate: taskDelegate)
                        } onCancel: {
                            box.cancel()
                        }

                        box.task = bytes.task
                        currentTask = bytes.task

                        guard let manualRedirect = try taskDelegate.takePendingManualBodyRedirect() else {
                            return (bytes, response)
                        }

                        currentRequest = manualRedirect
                    }
                }

                let (bytes, response) = try await resolveExchange()

                let responseHead: Internals.ResponseHead
                do {
                    responseHead = try taskDelegate.responseHead(for: response)
                } catch {
                    // A refused redirect's 3xx, or a non-HTTP response: nobody will read its
                    // body, so don't leave the task running to deliver it.
                    bytes.task.cancel()
                    throw error
                }

                // A response head can only exist once the request body finished sending, so this
                // is also where `upload` closes, mirroring
                // `Internals.ClientResponseReceiver.didReceiveHead`. `executeSessionTask` closes it
                // again once the exchange ends, for the paths that never get here.
                upload.close()

                // Attached before `head` is ever read from, and before any body byte is appended:
                // ordered against every `downloadBuffer.append(_:)` by
                // `Internals.DownloadBuffer`'s own queue, the same guarantee
                // `Internals.ClientResponseReceiver.didReceiveHead` relies on.
                //
                // Skipped whenever this response still needs this package's own decompression:
                // the tee here captures wire bytes upstream of that step, so caching would
                // persist the still-compressed body under a cached head that (on replay, which
                // never re-runs decompression) claims it's already decoded. See
                // `Internals.ManualDecompressionDispatch.requiresManualDecoding(for:)`.
                if !decompressionDispatch.requiresManualDecoding(for: responseHead),
                    let cacheStream = cache?(responseHead)
                {
                    downloadBuffer.cacheStream(cacheStream)
                }

                transferControl?.observer?.didReceiveHead(responseHead)
                head.append(.success(responseHead))
                head.close()
                isHeadResolved = true

                var state = resumption.map { Internals.DownloadResumptionState(policy: $0) }

                state?.didReceiveOriginalHead(
                    responseHead,
                    method: request.httpMethod ?? "GET",
                    requestHeaderNames: request.allHTTPHeaderFields?.keys.map { $0 } ?? []
                )

                var deliveredBytes: Int64 = .zero

                do {
                    try await pumpResponseBody(
                        bytes,
                        readingMode: readingMode,
                        into: downloadBuffer,
                        flowControl: flowControl,
                        deliveredBytes: &deliveredBytes
                    )
                } catch {
                    let error = taskDelegate.substitutingRecordedError(for: error)

                    // This exchange is over whatever comes next: a continuation is another one.
                    taskDelegate.recordFailure(error, of: currentTask)
                    isFailureRecorded = true

                    guard var state, let transferControl else {
                        throw error
                    }

                    state.deliveredBytes = deliveredBytes

                    try await resumeDownload(
                        after: error,
                        state: &state,
                        session: session,
                        request: request,
                        continuationDelegate: continuationDelegate,
                        box: box,
                        readingMode: readingMode,
                        downloadBuffer: downloadBuffer,
                        flowControl: flowControl,
                        transferControl: transferControl
                    )
                }

                transferControl?.observer?.didChange(.finished)
                downloadBuffer.close()
            } catch {
                let error = taskDelegate.substitutingRecordedError(for: error)

                // Already recorded when it came from the body or from a continuation, which each
                // record their own exchange's failure.
                if !isFailureRecorded {
                    taskDelegate.recordFailure(error, of: currentTask)
                }

                transferControl?.observer?.didChange(.failed(error))

                if !isHeadResolved {
                    head.append(.failure(error))
                    head.close()
                }

                downloadBuffer.failed(error)
            }
        }

        /// Continues a download whose exchange failed after its head, on new exchanges asking
        /// for the rest with `Range`/`If-Range`, for as long as the failures are transport
        /// failures and `state`'s budget lasts.
        ///
        /// Each continuation's head is validated (`Internals.RangeResumptionPlan.validate`)
        /// before a single byte of its body reaches `downloadBuffer`; anything but exactly the
        /// rest of the same representation ends the download with the mismatch.
        ///
        /// A failure while suspended -- typically the request timing out because nothing moved
        /// for `timeoutIntervalForRequest` -- only reconnects once the execution is resumed:
        /// a new connection would otherwise just idle out the same way.
        ///
        /// - Returns: Once the body is complete.
        /// - Throws: Whatever should end the download: the last transport failure once the budget
        ///   is spent, a mismatch, or the cancellation.
        private static func resumeDownload(
            after error: Error,
            state: inout Internals.DownloadResumptionState,
            session: URLSession,
            request: URLRequest,
            continuationDelegate: @Sendable (URLRequest) -> TaskDelegate,
            box: CancellableTaskBox,
            readingMode: Internals.DownloadStep.ReadingMode,
            downloadBuffer: Internals.DownloadBuffer,
            flowControl: Internals.FlowControlWindow,
            transferControl: Internals.TransferControl
        ) async throws {
            var failure = error

            while true {
                guard
                    !Task.isCancelled,
                    isTransientTransportFailure(failure),
                    let attempt = state.nextAttempt()
                else {
                    throw failure
                }

                // Released by the seed along with everything else when the exchange is cancelled,
                // which is what ends this wait then; the handler covers any other cancellation.
                await withTaskCancellationHandler {
                    await transferControl.waitUntilResumed()
                } onCancel: {
                    transferControl.release()
                }

                if state.policy.delay > .zero {
                    try? await Task.sleep(nanoseconds: state.policy.delay)
                }

                guard !Task.isCancelled else {
                    throw URLError(.cancelled)
                }

                transferControl.observer?.didChange(.reconnecting(attempt: attempt.number))

                var continuation = request

                for header in attempt.headers {
                    continuation.setValue(header.value, forHTTPHeaderField: header.name)
                }

                let taskDelegate = continuationDelegate(continuation)
                var deliveredBytes = state.deliveredBytes
                var attemptTask: URLSessionTask?

                do {
                    let (bytes, response) = try await withTaskCancellationHandler {
                        try await session.bytes(for: continuation, delegate: taskDelegate)
                    } onCancel: {
                        box.cancel()
                    }

                    box.task = bytes.task
                    attemptTask = bytes.task

                    let outcome: Internals.RangeResumptionPlan.Continuation
                    do {
                        outcome = try attempt.plan.validate(
                            taskDelegate.responseHead(for: response),
                            resumingAt: attempt.offset
                        )
                    } catch {
                        bytes.task.cancel()
                        throw error
                    }

                    if outcome == .alreadyComplete {
                        bytes.task.cancel()
                        return
                    }

                    try await pumpResponseBody(
                        bytes,
                        readingMode: readingMode,
                        into: downloadBuffer,
                        flowControl: flowControl,
                        deliveredBytes: &deliveredBytes
                    )

                    return
                } catch {
                    state.deliveredBytes = deliveredBytes
                    failure = taskDelegate.substitutingRecordedError(for: error)

                    taskDelegate.recordFailure(failure, of: attemptTask)
                }
            }
        }

        /// Whether `error` means the connection was lost or couldn't be (re)established -- the
        /// failures a download continuation can recover from -- as opposed to a cancellation, a
        /// TLS/trust or redirect-policy failure, or a malformed response, which it can't.
        static func isTransientTransportFailure(_ error: Error) -> Bool {
            guard let error = error as? URLError else {
                return false
            }

            switch error.code {
            case .networkConnectionLost, .timedOut, .notConnectedToInternet, .cannotConnectToHost,
                .cannotFindHost, .dnsLookupFailed, .dataNotAllowed:
                return true
            default:
                return false
            }
        }

        /// Puts a materialized upload body where `bytes(for:delegate:)` will find it: on the
        /// request itself.
        ///
        /// - `.data` becomes `httpBody`, which `URLSession` frames with its own `Content-Length`
        ///   and resends by itself on a redirect or retry.
        /// - `.file`/`.existingFile` become an `httpBodyStream` reading the file, with an explicit
        ///   `Content-Length` of its size, so the request is framed exactly as
        ///   `uploadTask(with:fromFile:)` framed it (without one, `URLSession` switches to chunked
        ///   transfer encoding). A resend asks `TaskDelegate` for a fresh stream over the same file
        ///   (`needNewBodyStream`).
        ///
        /// The `InputStream` here is Foundation's own file-backed one, which is not affected by
        /// the CFNetwork end-of-body bug `Internals.URLSessionUploadFile`'s header comment
        /// describes: that bug was only ever reproduced with custom `InputStream`s through
        /// `uploadTask(withStreamedRequest:)`. Verified end to end, fixed-length and chunked, and
        /// across 307/308 redirects that resend the body.
        ///
        /// - Returns: The file a resend has to reopen, if the body is file-backed.
        private static func attachUploadBody(
            _ uploadBody: Internals.URLSessionUploadFile.Materialized?,
            to request: inout URLRequest
        ) throws -> URL? {
            let fileURL: URL

            switch uploadBody {
            case nil:
                return nil
            case .data(let data):
                request.httpBody = data
                return nil
            case .file(let bufferURL):
                fileURL = bufferURL.absoluteURL()
            case .existingFile(let url):
                fileURL = url
            }

            // Checked up front, not left to the stream: `uploadTask(with:fromFile:)` used to send
            // a file that had gone missing as an empty body, with a `Content-Length: 0`, and
            // report success.
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

            guard
                let size = (attributes[.size] as? NSNumber)?.int64Value,
                let stream = InputStream(url: fileURL)
            else {
                throw URLError(.cannotOpenFile, userInfo: [NSURLErrorFailingURLErrorKey: fileURL])
            }

            request.httpBodyStream = stream
            request.setValue(String(size), forHTTPHeaderField: "Content-Length")
            return fileURL
        }

        /// Invalidates the underlying `URLSession`. Mirrors `Internals.Client.shutdown()`, read
        /// by `Internals.ClientManager`'s idle-cleanup sweep. Idempotent and a no-op while a
        /// request is still in flight, same guard as the NIO counterpart.
        ///
        /// - Returns: `true` if this call actually invalidated the session, `false` if it was
        /// already closed or is still busy.
        package func shutdown() async throws -> Bool {
            guard !isRunning else {
                return false
            }

            let shouldShutdown = lock.withLock { () -> Bool in
                guard !_isClosed else {
                    return false
                }

                _isClosed = true
                return true
            }

            guard shouldShutdown else {
                return false
            }

            // No outstanding tasks per the `isRunning` guard above, so there is nothing to drain.
            // Unlike `HTTPClient.shutdown()`, invalidation here is immediate, not awaited.
            session.invalidateAndCancel()
            return true
        }
    }
}

extension Internals.URLSessionClient {

    /// `URLSession` only ever hands back a non-`HTTPURLResponse` for a non-HTTP(S) scheme, which
    /// RequestDL never builds a request for; this should be unreachable in practice.
    package struct UnexpectedURLResponseError: Error, Sendable {
        package let response: URLResponse
    }

    /// A streamed-upload task (`execute(request:streaming:delegate:onUploadProgress:)`) completed
    /// with no error and yet never called `urlSession(_:dataTask:didReceive:completionHandler:)`.
    /// Should be unreachable given `URLSession`'s own contract (every task either fails or
    /// eventually receives a response), kept as a named error rather than force-unwrapping.
    package struct MissingURLResponseError: Error, Sendable {}

    /// The proxy rejected the configured `Internals.Proxy.Authorization` credentials. Mirrors
    /// `HTTPClientError.proxyAuthenticationRequired` from the NIO executor.
    package struct ProxyAuthenticationFailedError: Error, Sendable {}

    /// Thrown when a redirect chain exceeds `Internals.RedirectConfiguration.follow(max:_:)`'s
    /// `max`. Mirrors `HTTPClientError.redirectLimitReached` from the NIO executor.
    package struct RedirectLimitReachedError: Error, Sendable {}

    /// Thrown when a redirect would revisit an already-visited URL and
    /// `Internals.RedirectConfiguration.follow(_:allowCycles:)`'s `allowCycles` is `false`.
    /// Mirrors `HTTPClientError.redirectCycleDetected` from the NIO executor.
    package struct RedirectCycleDetectedError: Error, Sendable {}

    /// Lets a `withTaskCancellationHandler`'s `onCancel` closure reach a `URLSessionTask` that a
    /// concurrently-running `operation` closure is still in the middle of creating.
    ///
    /// `onCancel` can fire the instant cancellation is requested, including strictly before
    /// `operation` ever assigns `task`, so a plain `URLSessionTask?` written to after the fact
    /// could miss a cancellation that arrived in that gap. `task`'s setter checks for exactly that
    /// ordering and cancels immediately instead of losing it.
    fileprivate final class CancellableTaskBox: @unchecked Sendable {

        private let lock = Lock()
        private var _task: URLSessionTask?
        private var _isCancelled = false

        var task: URLSessionTask? {
            get { lock.withLock { _task } }
            set {
                let shouldCancelImmediately = lock.withLock {
                    _task = newValue
                    return _isCancelled
                }
                if shouldCancelImmediately {
                    newValue?.cancel()
                }
            }
        }

        func cancel() {
            let task = lock.withLock {
                _isCancelled = true
                return _task
            }
            task?.cancel()
        }
    }
}

/// `Internals.URLSessionClient`'s own per-request delegate: redirect enforcement, proxy
/// authentication, and, when this client was built with a `secureConnection`, TLS challenge
/// handling, none of which URLSession has a configuration-level API for; all must instead be
/// answered through delegate callbacks. A TLS challenge this delegate's
/// own `tlsDelegate` can't answer (no `identityPolicy`, or a different host) falls through to
/// `forwardingDelegate`, the caller-supplied `delegate` `execute(request:delegate:)` was given,
/// since URLSession allows only one delegate per task.
extension Internals.URLSessionClient {

    fileprivate final class TaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {

        // MARK: - Private properties

        private let redirectConfiguration: Internals.RedirectConfiguration
        private let proxyAuthorization: Internals.Proxy.Authorization?
        private let tlsDelegate: TLSDelegate?
        private let forwardingDelegate: URLSessionTaskDelegate?
        private let onUploadProgress: (@Sendable (Int, Int) -> Void)?
        /// Set for the streamed-download `execute(request:readingMode:delegate:)` path only.
        /// `nil` for the other two, which is exactly the switch `didReceive
        /// response:completionHandler:`/`didReceive data:`/`didCompleteWithError:` use below to
        /// tell which of the three modes this instance is answering for.
        private let downloadBuffer: Internals.DownloadBuffer?
        /// Releases the throttle slot `execute(request:readingMode:delegate:)` acquired. See
        /// that method's own doc comment for why it can't just `defer { release() }` the way the
        /// other two `execute` overloads do.
        private let onDownloadComplete: (@Sendable () -> Void)?
        /// A fresh `httpBodyStream` for the request body, set only by `executeSessionTask`: over the
        /// same file again for a file-backed upload, or a new pair from
        /// `Internals.URLSessionUploadBodyPump` for a suspendable one. What `needNewBodyStream`
        /// answers with.
        private let makeBodyStream: (@Sendable () -> InputStream?)?
        /// The initial request's `Content-Length`, which a manual redirect resend reattaches.
        private let bodyLength: String?
        /// Where the transactions `URLSession` measured are reported. Set only by
        /// `executeSessionTask`, the one path whose result carries metrics to the caller.
        private let metrics: Internals.RequestMetricsCollector?
        private let lock = Lock()

        // MARK: - Unsafe properties

        /// All visited URLs, starting with the request's own. Mirrors `RedirectState.visited`.
        private var _visited: [String]
        private var _redirectError: Error?
        /// A redirect `willPerformHTTPRedirection` decided to follow but refused to hand back to
        /// `URLSession` itself, because this task's body is file-backed (`makeBodyStream` set): see
        /// that method's own doc comment for why. `runExchange` takes this, attaches a fresh
        /// stream, and reissues the request itself as a new `bytes(for:delegate:)` call.
        private var _pendingManualBodyRedirect: URLRequest?
        /// Set once the proxy has rejected the configured credentials and the challenge was
        /// cancelled; reported in place of the `NSURLErrorCancelled` that cancelling produces. See
        /// `substitutingRecordedError(for:)`.
        private var _proxyAuthenticationError: Error?
        /// The most recently sent request, updated on every followed redirect. Together with
        /// `_history`, lets `.strategy` mode reconstruct the same per-redirect context the NIO
        /// executor builds from its own `HTTPClientRequestResponse` history.
        private var _lastRequest: URLRequest
        private var _history: [Internals.RedirectHistoryEntry] = []
        /// Redirects followed under `.strategy` mode specifically, independent of `_history`,
        /// which accumulates regardless of mode, mirroring the NIO adapter's own
        /// `customRedirectCount` (incremented only when `.strategy` chooses `.follow`).
        private var _strategyRedirectCount = 0
        /// Response accumulation for the streamed-upload path only. The buffered path never
        /// touches these, since `session.data(for:delegate:)` does its own accumulation
        /// regardless of what extra `URLSessionDataDelegate` methods this class implements.
        private var _response: URLResponse?
        private var _responseData: Data
        /// Set by `execute(request:streaming:delegate:onUploadProgress:)` right after
        /// construction, read from `urlSession(_:task:didCompleteWithError:)` once the streamed
        /// upload task finishes either way.
        private var _completion: ((Result<(head: Internals.ResponseHead, body: Data), Error>) -> Void)?
        /// Set by `execute(request:readingMode:delegate:)` right after construction, resolved from
        /// `didReceive response:completionHandler:` (the common case) or, if the task fails before
        /// a response ever arrives, from `didCompleteWithError:` instead. Guarded by `_headResolved`
        /// so whichever fires first wins and the other is a no-op.
        private var _headCompletion: ((Result<Internals.DownloadStep, Error>) -> Void)?
        private var _headResolved = false
        /// Where in `metrics` the last transaction of each task of this delegate was recorded, by
        /// `taskIdentifier`, so an error learned afterwards lands on the right one.
        private var _transactionIndices: [Int: Int] = [:]
        /// Errors of a task whose metrics had not been reported yet, by `taskIdentifier`.
        private var _pendingFailures: [Int: any Error] = [:]
        /// The error of an exchange that failed before it had a task at all, waiting for the next
        /// transaction reported. With a manual body redirect (see `completeRedirect(with:_:)`) it
        /// can land on an earlier hop's transaction, if that hop's metrics are reported after the
        /// failing exchange has already started.
        private var _unattributedFailure: (any Error)?
        /// The last transaction reported, and whether it ever got a response. A transaction that
        /// did not cannot be a hop that went through, so a failure with no task of its own can
        /// only be that one's.
        private var _lastTransaction: (index: Int, gotResponse: Bool)?

        // MARK: - Internal properties

        /// Set once a redirect is refused for violating `redirectConfiguration`. `nil` when every
        /// redirect (if any) stayed within it, when there was none to begin with, or under
        /// `.disallow` (declining to follow is not a failure there).
        var redirectError: Error? {
            lock.withLock { _redirectError }
        }

        var completion: ((Result<(head: Internals.ResponseHead, body: Data), Error>) -> Void)? {
            get { lock.withLock { _completion } }
            set { lock.withLock { _completion = newValue } }
        }

        var headCompletion: ((Result<Internals.DownloadStep, Error>) -> Void)? {
            get { lock.withLock { _headCompletion } }
            set { lock.withLock { _headCompletion = newValue } }
        }

        // MARK: - Inits

        init(
            redirectConfiguration: Internals.RedirectConfiguration,
            initialRequest: URLRequest,
            proxyAuthorization: Internals.Proxy.Authorization?,
            tls tlsDelegate: TLSDelegate?,
            forwarding delegate: URLSessionTaskDelegate?,
            onUploadProgress: (@Sendable (Int, Int) -> Void)? = nil,
            downloadBuffer: Internals.DownloadBuffer? = nil,
            onDownloadComplete: (@Sendable () -> Void)? = nil,
            makeBodyStream: (@Sendable () -> InputStream?)? = nil,
            metrics: Internals.RequestMetricsCollector? = nil
        ) {
            self.redirectConfiguration = redirectConfiguration
            self.proxyAuthorization = proxyAuthorization
            self.tlsDelegate = tlsDelegate
            self.forwardingDelegate = delegate
            self.onUploadProgress = onUploadProgress
            self.downloadBuffer = downloadBuffer
            self.onDownloadComplete = onDownloadComplete
            self.makeBodyStream = makeBodyStream
            self.metrics = metrics
            self.bodyLength = initialRequest.value(forHTTPHeaderField: "Content-Length")
            self._lastRequest = initialRequest
            self._visited = [initialRequest.url?.absoluteString ?? ""]
            self._responseData = Data()
        }

        // MARK: - Internal methods

        /// Enforces `Internals.RedirectConfiguration` for this task.
        ///
        /// URLSession has no native "max redirects" / "allow cycles" concept:
        /// `willPerformHTTPRedirection` only ever offers "follow this exact request" or "don't,
        /// and treat the redirect response as final." Both the counting and the cycle detection
        /// below are a direct port of what AsyncHTTPClient's own `RedirectState`
        /// (`RedirectState.swift`, vendored in `async-http-client`) does for the NIO executor, so
        /// the two backends fail identically for the same configuration.
        ///
        /// `.disallow` needs no tracking at all: every redirect is refused via
        /// `completionHandler(nil)`, same as AsyncHTTPClient handing back the 3xx response
        /// untouched when `redirectHandler` is `nil`. This is not a `redirectError`, since declining to
        /// follow is not itself a failure.
        ///
        /// Both `.follow` and `.strategy` strip `Authorization`/`Cookie`/`Origin`/
        /// `Proxy-Authorization` from `request` when it no longer shares the previously sent
        /// request's origin (scheme, host, and port). `URLSession` does not do this on its own,
        /// unlike the NIO executor's `followingRedirect`/`transformRequestForRedirect`, which this
        /// mirrors so a redirect leaking credentials to a different host fails the same way under
        /// either transport.
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            switch redirectConfiguration {
            case .disallow:
                completionHandler(nil)

            case .follow(let max, let allowCycles):
                let redirectURL = request.url?.absoluteString ?? ""

                let outcome: Result<Void, Error> = lock.withLock {
                    guard _visited.count <= max else {
                        return .failure(Internals.URLSessionClient.RedirectLimitReachedError())
                    }

                    guard allowCycles || !_visited.contains(redirectURL) else {
                        return .failure(Internals.URLSessionClient.RedirectCycleDetectedError())
                    }

                    _visited.append(redirectURL)
                    return .success(())
                }

                switch outcome {
                case .success:
                    let sanitizedRequest = sanitizedForRedirect(request)
                    // `historyEntry(for:)` takes `lock` itself to read `_lastRequest`, so it must
                    // resolve it before entering this block, not inside it, or it deadlocks
                    // `Lock`, which is not reentrant.
                    let entry = historyEntry(for: response)
                    lock.withLock {
                        _history.append(entry)
                        _lastRequest = sanitizedRequest
                    }
                    completeRedirect(with: sanitizedRequest, completionHandler)
                case .failure(let error):
                    lock.withLock { _redirectError = error }
                    completionHandler(nil)
                }

            case .strategy(let strategy):
                let sanitizedRequest = sanitizedForRedirect(request)
                let entry = historyEntry(for: response)

                let context = lock.withLock { () -> Internals.RedirectContext in
                    _history.append(entry)
                    return Internals.RedirectContext(
                        redirectRequest: .init(sanitizedRequest),
                        response: .init(response),
                        history: _history,
                        redirectCount: _strategyRedirectCount
                    )
                }

                let decision: Internals.RedirectDecision
                do {
                    decision = try strategy.redirectDecision(for: context)
                } catch {
                    lock.withLock { _redirectError = error }
                    completionHandler(nil)
                    return
                }

                switch decision {
                case .doNotFollow:
                    completionHandler(nil)
                case .follow(let redirectRequest):
                    let newRequest = sanitizedRequest.applyingRedirectDecision(redirectRequest)
                    lock.withLock {
                        _lastRequest = newRequest
                        _strategyRedirectCount += 1
                    }
                    completeRedirect(with: newRequest, completionHandler)
                }
            }
        }

        // MARK: - Private methods

        /// Hands `request` to `URLSession` to follow automatically, unless this task's body is
        /// file-backed and `request` still carries one (i.e. its method wasn't downgraded to
        /// `GET`/`HEAD`) -- observed directly, on watchOS specifically: `URLSession` there
        /// neither calls `needNewBodyStream` for such a resend nor honours a stream attached to
        /// the request returned from this very delegate method, and instead silently resends the
        /// *original* request's stream, already exhausted by the first send. Every other tested
        /// platform (macOS, iOS, iPadOS, tvOS, Catalyst) does call `needNewBodyStream` here on
        /// its own and sends the body correctly.
        ///
        /// So for this one combination, this refuses the automatic follow (`completionHandler(nil)`,
        /// same as `.disallow`) and defers to `runExchange`, which takes `request` from
        /// `takePendingManualBodyRedirect()`, attaches a fresh stream itself, and reissues it as a
        /// brand new `bytes(for:delegate:)` call -- a genuinely new task, not a continuation of
        /// the redirected one, so the platform quirk above (specific to *resending* a stream on
        /// the same continuing exchange) never applies to it.
        private func completeRedirect(with request: URLRequest, _ completionHandler: (URLRequest?) -> Void) {
            guard
                makeBodyStream != nil,
                let method = request.httpMethod,
                !["GET", "HEAD"].contains(method.uppercased())
            else {
                completionHandler(request)
                return
            }

            lock.withLock { _pendingManualBodyRedirect = request }
            completionHandler(nil)
        }

        /// The request that produced `response`, per `_lastRequest`: the request one hop
        /// before `request` in `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)`.
        private func historyEntry(for response: HTTPURLResponse) -> Internals.RedirectHistoryEntry {
            lock.withLock {
                .init(request: .init(_lastRequest), response: .init(response))
            }
        }

        /// Strips `Authorization`/`Cookie`/`Origin`/`Proxy-Authorization` from `request` when it
        /// no longer shares `_lastRequest`'s origin. See the doc comment on
        /// `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)`.
        private func sanitizedForRedirect(_ request: URLRequest) -> URLRequest {
            let previousURL = lock.withLock { _lastRequest.url }

            guard
                let previousURL,
                let newURL = request.url,
                !previousURL.hasTheSameOrigin(as: newURL)
            else {
                return request
            }

            var sanitized = request
            for header in ["Origin", "Cookie", "Authorization", "Proxy-Authorization"] {
                sanitized.setValue(nil, forHTTPHeaderField: header)
            }
            return sanitized
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.isProxy(),
                challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic,
                let credential = proxyCredential()
            {
                // Only the first time. A challenge that has already failed means the proxy just
                // rejected this very credential, and answering with it again only repeats the
                // rejection: `URLSession` keeps re-challenging for as long as the delegate keeps
                // answering, observed as 81-340 `CONNECT`s within a fraction of a second against a
                // proxy rejecting the configured credentials, before `URLSession` gave up on its
                // own.
                //
                // Cancelled rather than left to default handling: measured side by side, both
                // `.performDefaultHandling` and `.rejectProtectionSpace` usually failed the request
                // at once but, about one run in three, left it waiting out the whole request
                // timeout instead. Cancelling fails it every time, immediately. The resulting
                // `NSURLErrorCancelled` would read as the caller having cancelled, though, so the
                // exchange reports `ProxyAuthenticationFailedError` instead (see
                // `substitutingRecordedError(for:)`): the counterpart to AsyncHTTPClient's
                // `proxyAuthenticationRequired` on the NIO executor.
                guard challenge.previousFailureCount == .zero else {
                    lock.withLock { _proxyAuthenticationError = ProxyAuthenticationFailedError() }
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }

                completionHandler(.useCredential, credential)
                return
            }

            // `tlsDelegate`/`identityPolicy` hold the trust configuration (pinning, custom trust
            // roots, revocation) resolved for the *destination* host, and are deliberately still
            // consulted for a redirect target (a different destination host) -- see
            // `URLSessionIdentityPolicy.handle`'s own doc comment. A proxy challenge is not that:
            // when the configured proxy terminates TLS itself (an HTTPS-inspecting forward proxy),
            // URLSession delivers a server-trust challenge for the *proxy's* own certificate, with
            // `isProxy() == true`. Routing that to the destination's pinning policy would either
            // reject a legitimate proxy outright under strict pinning, or, under `.audit`, silently
            // skip meaningful validation of the proxy's certificate. Proxy challenges besides the
            // HTTPBasic one just handled must fall through to `forwardingDelegate`/default handling
            // instead.
            if let tlsDelegate, !challenge.protectionSpace.isProxy() {
                tlsDelegate.urlSession(session, task: task, didReceive: challenge, completionHandler: completionHandler)
                return
            }

            let forwarded =
                forwardingDelegate?.urlSession?(
                    session,
                    task: task,
                    didReceive: challenge,
                    completionHandler: completionHandler
                ) != nil

            if !forwarded {
                completionHandler(.performDefaultHandling, nil)
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64
        ) {
            onUploadProgress?(Int(bytesSent), Int(totalBytesExpectedToSend))
        }

        /// Reports every transaction of the task, one per redirect hop and one per retry on a fresh
        /// connection, in the order they happened.
        ///
        /// Arrives once the task has ended, so the last transaction is already complete. Forwarded
        /// afterwards, since `URLSession` allows only one delegate per task and this one stands
        /// between it and the caller's.
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            if let collector = self.metrics {
                var transactions = metrics.transactionMetrics.map(Internals.TransactionMetrics.init)

                lock.withLock {
                    // The task ended with an error before its metrics arrived: it is the last
                    // transaction's, since every earlier one (a redirect hop) went through.
                    if !transactions.isEmpty {
                        if let failure = _pendingFailures.removeValue(forKey: task.taskIdentifier) {
                            transactions[transactions.count - 1].error = failure
                        } else if let failure = _unattributedFailure {
                            transactions[transactions.count - 1].error = failure
                            _unattributedFailure = nil
                        }
                    }

                    var lastIndex: Int?

                    for transaction in transactions {
                        lastIndex = collector.append(transaction)
                    }

                    if let lastIndex {
                        _transactionIndices[task.taskIdentifier] = lastIndex
                        _lastTransaction = (lastIndex, transactions.last?.responseStart != nil)
                    }
                }
            }

            forwardingDelegate?.urlSession?(session, task: task, didFinishCollecting: metrics)
        }

        /// Records the error that ended `task`, on its last transaction.
        ///
        /// `URLSession` reports an error for the task as a whole (`didCompleteWithError:`, which
        /// `bytes(for:delegate:)` consumes itself), never for a single transaction, so it has to
        /// come from whoever runs the exchange. It can arrive before or after the task's metrics,
        /// and both orders end up on the same transaction.
        ///
        /// - Parameter task: The task that failed, or `nil` when the exchange failed before it had
        ///   one, as when the connection could not be made.
        func recordFailure(_ error: any Error, of task: URLSessionTask?) {
            guard let collector = metrics else {
                return
            }

            lock.withLock {
                guard let task else {
                    // Its metrics may already be in, which is the usual order for a connection that
                    // could not be made.
                    if let last = _lastTransaction, !last.gotResponse {
                        collector.setError(error, at: last.index)
                    } else {
                        _unattributedFailure = error
                    }

                    return
                }

                if let index = _transactionIndices[task.taskIdentifier] {
                    collector.setError(error, at: index)
                } else {
                    _pendingFailures[task.taskIdentifier] = error
                }
            }
        }

        /// Hands `URLSession` a fresh body stream (`makeBodyStream`) when it has to send the
        /// request body again: a 307/308 redirect, an authentication retry, a retry on a connection
        /// that turned out to be stale. Only ever asked for an `httpBodyStream` body, which only
        /// `executeSessionTask` builds (see `attachUploadBody(_:to:)`);
        /// `uploadTask(with:fromFile:)` and `httpBody` resend by themselves.
        ///
        /// Never answers `nil` while leaving the task running: observed directly, `URLSession`
        /// does not fail the task on a `nil` answer, it asks again, millions of times, until the
        /// request times out. If there's no body to give, the task is cancelled first.
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void
        ) {
            guard let stream = makeBodyStream?() else {
                task.cancel()
                completionHandler(nil)
                return
            }

            completionHandler(stream)
        }

        /// `error`, unless this delegate itself caused it by cancelling a challenge it had a
        /// reason to refuse, in which case that reason. Every way an exchange can fail runs its
        /// error through this: `didCompleteWithError:` for the `dataTask`/`uploadTask` overloads,
        /// and `executeSessionTask`'s `runExchange` for the `bytes(for:delegate:)` one.
        func substitutingRecordedError(for error: Error) -> Error {
            lock.withLock { _proxyAuthenticationError } ?? error
        }

        /// The redirect `willPerformHTTPRedirection` deferred to `runExchange` (see
        /// `_pendingManualBodyRedirect`'s own doc comment), with a fresh stream over
        /// `makeBodyStream`'s stream already attached and ready to send -- `nil` when there's nothing
        /// pending. Cleared so it's only ever taken once.
        ///
        /// - Throws: if the body's file is gone by the time of the resend, the same
        /// failure `attachUploadBody(_:to:)` raises for the initial request, rather than
        /// silently sending an empty or wrong body.
        func takePendingManualBodyRedirect() throws -> URLRequest? {
            guard
                let pending = lock.withLock({
                    defer { _pendingManualBodyRedirect = nil }
                    return _pendingManualBodyRedirect
                })
            else {
                return nil
            }

            guard let stream = makeBodyStream?() else {
                throw URLError(.cannotOpenFile)
            }

            var request = pending
            request.httpBodyStream = stream

            if let bodyLength {
                request.setValue(bodyLength, forHTTPHeaderField: "Content-Length")
            }

            return request
        }

        /// The response head for `executeSessionTask`, which gets `response` from
        /// `bytes(for:delegate:)` rather than from `didReceive response:completionHandler:`.
        /// Applies the same checks `resolveHead(with:downloadBuffer:)` does there: a redirect this
        /// delegate refused for violating `redirectConfiguration` fails the exchange with
        /// `redirectError` (the 3xx `URLSession` then returns is not a real response), and a
        /// non-HTTP response fails it with `UnexpectedURLResponseError`.
        func responseHead(for response: URLResponse) throws -> Internals.ResponseHead {
            if let redirectError = lock.withLock({ _redirectError }) {
                throw redirectError
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw UnexpectedURLResponseError(response: response)
            }

            return Internals.ResponseHead(httpResponse)
        }

        /// Response-side counterpart to `needNewBodyStream` above. Exercised by the
        /// streamed-upload path (which, unlike the buffered path's `session.data(for:delegate:)`,
        /// has no built-in response accumulation of its own to fall back on) and, differently, by
        /// the streamed-download path, which resolves `headCompletion` right here instead of
        /// waiting for the whole body like the other two modes do.
        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            lock.withLock { _response = response }

            if let downloadBuffer {
                resolveHead(with: response, downloadBuffer: downloadBuffer)
            }

            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard let downloadBuffer else {
                lock.withLock { _responseData.append(data) }
                return
            }

            // Sync, deliberately: `Internals.DownloadBuffer.append(_:)` enqueues onto an
            // ordered queue, and submission order has to match arrival order. Building the
            // `Internals.DataBuffer` on a detached `Task` (its usual, `async`, in-memory-or-file
            // generic initializer) would let two chunks race to enqueue and reassemble the body
            // out of order. `Internals.Buffer`'s own "Synchronous construction, in memory only"
            // extension exists for precisely this reason (see its doc comment, which calls out a
            // NIO delegate callback as the original motivating case; this is the same shape of
            // problem one layer up, for `URLSessionDataDelegate` instead of
            // `HTTPClientResponseDelegate`).
            let byteURL = Internals.ByteURL()
            byteURL.replace(with: data)
            downloadBuffer.append(Internals.DataBuffer(byteURL))
        }

        /// Resolves `completion`/`headCompletion`: the streamed-upload and streamed-download
        /// paths' only way to learn a task is done, since neither goes through
        /// `session.data(for:delegate:)`'s own `async` completion. A no-op for the buffered path,
        /// where `completion` is never set.
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let downloadBuffer {
                defer { onDownloadComplete?() }

                // A failure before any response ever arrived (e.g. connection refused) means
                // `didReceive response:` never ran and `headCompletion` is still unresolved.
                // Resolve it now rather than leaving `execute(request:readingMode:delegate:)`
                // suspended forever. `resolveHead(with:downloadBuffer:)` is a no-op if a response
                // already resolved it, so this is safe to call unconditionally.
                if let error {
                    let error = substitutingRecordedError(for: error)
                    resolveHeadWithFailure(error)
                    downloadBuffer.failed(error)
                } else {
                    downloadBuffer.close()
                }

                return
            }

            guard let completion = lock.withLock({ _completion }) else {
                return
            }

            if let redirectError = lock.withLock({ _redirectError }) {
                completion(.failure(redirectError))
                return
            }

            if let error {
                completion(.failure(substitutingRecordedError(for: error)))
                return
            }

            let (response, data) = lock.withLock { (_response, _responseData) }

            guard let response else {
                completion(.failure(MissingURLResponseError()))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(UnexpectedURLResponseError(response: response)))
                return
            }

            completion(.success((Internals.ResponseHead(httpResponse), data)))
        }

        // MARK: - Private methods

        /// Resolves `headCompletion` from the response URLSession actually delivered:
        /// `didReceive response:completionHandler:`'s normal path. A no-op if `headCompletion`
        /// already resolved (guarded by `_headResolved`), which only happens if
        /// `didCompleteWithError:` beat it to a failure. Shouldn't happen given `URLSession`'s
        /// own callback ordering, kept anyway since resolving a completion handler twice is a
        /// trap, not a silent bug.
        private func resolveHead(with response: URLResponse, downloadBuffer: Internals.DownloadBuffer) {
            let completion = lock.withLock { () -> ((Result<Internals.DownloadStep, Error>) -> Void)? in
                guard !_headResolved else { return nil }
                _headResolved = true
                return _headCompletion
            }

            guard let completion else {
                return
            }

            if let redirectError = lock.withLock({ _redirectError }) {
                completion(.failure(redirectError))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(UnexpectedURLResponseError(response: response)))
                return
            }

            let head = Internals.ResponseHead(httpResponse)

            let totalSize =
                head.headerValues(named: "Content-Length")
                .lazy
                .flatMap { $0.split(separator: ",") }
                .map { $0.trimming(where: \.isWhitespace) }
                .compactMap { Int($0) }
                .max() ?? .zero

            completion(
                .success(
                    Internals.DownloadStep(
                        head: head,
                        bytes: Internals.AsyncBytes(
                            logger: nil,
                            totalSize: totalSize,
                            stream: downloadBuffer.stream
                        )
                    )
                )
            )
        }

        /// Resolves `headCompletion` with `error`. Only actually resolves anything if no
        /// response ever arrived to resolve it first (guarded by the same `_headResolved` flag
        /// `resolveHead(with:downloadBuffer:)` uses); called unconditionally from
        /// `didCompleteWithError:` so a connection-level failure before any response (refused,
        /// DNS failure, TLS failure) doesn't leave `execute(request:readingMode:delegate:)`
        /// suspended forever.
        private func resolveHeadWithFailure(_ error: Error) {
            let completion = lock.withLock { () -> ((Result<Internals.DownloadStep, Error>) -> Void)? in
                guard !_headResolved else { return nil }
                _headResolved = true
                return _headCompletion
            }

            completion?(.failure(error))
        }

        /// `.basic`/`.basicRawCredentials` only. `URLCredential` has exactly two shapes
        /// (user/password, identity/certificates), neither of which can carry an arbitrary
        /// bearer token, which is why `.bearer` proxy authorization is excluded from
        /// `.urlSession` entirely (`Internals.ExecutorIncompatibilityReason
        /// .proxyBearerAuthorizationUnderURLSession`) rather than attempted here.
        private func proxyCredential() -> URLCredential? {
            switch proxyAuthorization {
            case .basic(let username, let password):
                return URLCredential(user: username, password: password, persistence: .forSession)

            case .basicRawCredentials(let credentials):
                guard
                    let decoded = Data(base64Encoded: credentials),
                    let pair = String(data: decoded, encoding: .utf8)
                else {
                    return nil
                }

                let components = pair.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

                guard components.count == 2 else {
                    return nil
                }

                return URLCredential(
                    user: String(components[0]),
                    password: String(components[1]),
                    persistence: .forSession
                )

            case .bearer, nil:
                return nil
            }
        }
    }
}

// MARK: - Testing

@_spi(Testing)
extension Internals.URLSessionClient {

    /// The serial queue this client's session delivers its delegate callbacks on. Lets a test
    /// hold it up the way CPU contention would: the condition under which
    /// `URLSessionTask.suspend()` was observed to stop holding a response back, and which the
    /// back pressure in `executeSessionTask` has to survive.
    public var delegateQueueForTesting: OperationQueue {
        session.delegateQueue
    }
}

extension Internals.ResponseHead {

    init(_ response: HTTPURLResponse) {
        self.init(
            url: response.url?.absoluteString ?? "",
            status: Status(
                code: UInt(response.statusCode),
                reason: HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            ),
            // `HTTPURLResponse` does not expose the negotiated HTTP version, only
            // `URLSessionTaskMetrics`, via a delegate callback this non-streaming round trip has
            // no reason to collect. `LocalServer`, and every executor-neutral caller today,
            // speaks HTTP/1.1 only, so that is the safe assumption here.
            version: Version(minor: 1, major: 1),
            headers: response.allHeaderFields.compactMap { name, value in
                guard let name = name as? String, let value = value as? String else {
                    return nil
                }
                return HeaderField(name: name, value: value)
            },
            // Not observable per response over URLSession: connection reuse is entirely
            // internal to the session. `true` matches HTTP/1.1's own default.
            isKeepAlive: true
        )
    }
}

#endif
