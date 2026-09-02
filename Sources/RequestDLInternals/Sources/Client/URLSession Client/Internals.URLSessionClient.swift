//
// See LICENSE for this package's licensing information.
//

// Covers a single non-streaming request/response round trip (`Data` in, `Data` out), redirect
// enforcement, `.server` proxy support, disabling URLSession's own cookie jar, TLS/mTLS challenge
// handling, streamed request-body uploads, and streamed response-body downloads.

#if canImport(Darwin)

import NIOCore
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

        /// Whether this client currently has any request in flight -- mirrors
        /// `Internals.Client.isRunning`, read by `Internals.ClientManager`'s idle-cleanup sweep so
        /// a busy client is never recycled out from under an in-flight request.
        package var isRunning: Bool {
            operationQueue.isRunning
        }

        // MARK: - Private properties

        private let session: URLSession
        private let throttledExecutor: Internals.ThrottledExecutor
        /// Transport-agnostic in-flight counter also used by `Internals.Client` -- backs
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
        /// `Internals.URLSessionIdentityPolicy` -- including the Keychain round-trip a client
        /// identity needs -- and cached for the lifetime of this client, mirroring
        /// NIOSSL's own per-connection `TLSConfiguration` caching in `Internals.ClientManager`.
        /// `nil` when the resolved request carries no TLS customization at all.
        /// - Parameter redirectConfiguration: Defaults to AsyncHTTPClient's own default
        /// (`.follow(max: 5, allowCycles: false)`, see `HTTPClient.Configuration.RedirectConfiguration.init()`)
        /// so a caller that does not set `Internals.Session.Configuration.redirectConfiguration`
        /// gets identical behavior regardless of which executor the session resolves to.
        /// - Parameter proxy: Both `.http` (`.server`) and `.socks` are mapped onto
        /// `configuration` -- `.bearer` proxy authorization is the one thing that stays excluded
        /// from `.urlSession` upstream (`Internals.ExecutorIncompatibilityReason
        /// .proxyBearerAuthorizationUnderURLSession`), so a well-formed caller never passes that
        /// here -- see `Internals.Proxy.buildConnectionProxyDictionary()`'s doc comment for the
        /// per-platform status of this mapping.
        package init(
            configuration: URLSessionConfiguration,
            secureConnection: Internals.SecureConnection? = nil,
            redirectConfiguration: Internals.RedirectConfiguration = .follow(max: 5, allowCycles: false),
            proxy: Internals.Proxy? = nil,
            maximumConcurrentConnections: Int? = nil
        ) throws {
            var configuration = configuration
            if let proxy {
                configuration.connectionProxyDictionary = proxy.buildConnectionProxyDictionary()
            }

            // Required normalization, not optional: URLSession persists cookies in a jar by
            // default, the NIO executor has none at all -- without
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
        /// proxy authentication, and -- when this client was built with a `secureConnection` --
        /// the server-trust/client-certificate challenge (see `TaskDelegate` below) all run
        /// regardless of `delegate`; `delegate` is only consulted for a TLS challenge this client
        /// has no `identityPolicy` to answer.
        ///
        /// Deliberately not `session.data(for:request:delegate:)` -- a captured crash report
        /// (`EXC_BREAKPOINT`/`SIGTRAP`, entirely inside Foundation's own
        /// `NSURLSession.data(for:delegate:)` closures on the `com.apple.NSURLSession-work`
        /// queue, no frame of this package's own code anywhere in the crashing thread) confirms a
        /// real, if rare, bug in that bridge -- reproducible on an iOS Simulator under heavy
        /// concurrent test load, not this package's own delegate (`TaskDelegate`'s shared state
        /// is already lock-protected). Bridged by hand instead, the same way the streamed-upload
        /// overload below already does: build a plain `dataTask(with:)` with no completion
        /// handler of its own, so `TaskDelegate` (already `URLSessionDataDelegate`-conforming) is
        /// the *only* thing consuming the response/data, and let its own
        /// `didCompleteWithError:` -- which already knows how to turn `redirectError`/the
        /// accumulated response into exactly this method's return shape -- resolve `completion`
        /// once the task finishes. (An earlier version of this fix instead read `data`/`response`
        /// off a `dataTask(with:completionHandler:)` completion handler directly, alongside the
        /// same delegate -- reachable together, but not guaranteed to agree with each other:
        /// caught by `execute_whenRedirectChainExceedsMax_throwsRedirectLimitReachedError`, which
        /// started failing with `MissingURLResponseError` instead of the expected
        /// `RedirectLimitReachedError` once a redirect was actually refused.)
        ///
        /// `session.data(for:delegate:)` also cancelled its underlying `URLSessionTask`
        /// automatically when the awaiting Swift `Task` was cancelled -- a guarantee this hand
        /// bridge has to restore explicitly, via `CancellableTaskBox`, since nothing does that for
        /// a bare `withCheckedThrowingContinuation` on its own.
        package func execute(
            request: URLRequest,
            delegate: URLSessionTaskDelegate? = nil
        ) async throws -> (head: Internals.ResponseHead, body: Data) {
            // Waited on before anything else, mirroring `Internals.Client.execute` -- a session
            // configured with a limit must never let more requests than that reach the network,
            // whether the cap is enforced by the NIO or the URLSession executor.
            let release = await throttledExecutor.acquire()
            defer { release() }

            let operation = operationQueue.operation()
            defer { operation.complete() }

            let tlsDelegate = identityPolicy.flatMap { policy in
                request.url?.host.map { TLSDelegate(host: $0, policy: policy) }
            }

            let taskDelegate = TaskDelegate(
                redirectConfiguration: redirectConfiguration,
                initialURL: request.url?.absoluteString ?? "",
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
        /// front. Materializes `body` (any `AsyncSequence` of `ByteBuffer`; in practice
        /// `Internals.BodySequence`, or `RequestBody` itself from the `RequestDL` module, both of
        /// which conform) via `Internals.URLSessionUploadFile`, then uploads from whichever shape
        /// that produced -- `uploadTask(with:from:)` for a body small enough to just hold in
        /// memory, `uploadTask(with:fromFile:)` for one that spilled to disk.
        ///
        /// Deliberately does not drive `uploadTask(withStreamedRequest:)` + `needNewBodyStream`
        /// via a custom `InputStream`: that path has a confirmed CFNetwork bug where no custom
        /// `InputStream` (Swift subclass or a genuine `CFReadStream`) is ever recognized as
        /// reaching end-of-body. Neither of the two shapes used here goes through `InputStream` at
        /// all, so neither is affected; the file-backed one also re-reads the file itself for any
        /// retry/redirect that resends the body -- nothing here needs to hand back a fresh body
        /// more than once.
        ///
        /// - Parameter existingUploadFile: Set when the caller already knows `body`'s entire
        /// content is sitting untouched in this file (`RequestBody.wholeFileURL`, a
        /// `Payload(url:)`-only body) -- skips `Internals.URLSessionUploadFile.write(body:)`
        /// entirely rather than draining `body` only to recreate a copy of a file that already
        /// exists. `body` is still required in that case (for the generic `Body` type/call-site
        /// symmetry with the other overload below) but is never iterated.
        /// - Parameter onUploadProgress: Called once per `didSendBodyData` callback, in delivery
        /// order, with `(bytesSentThisCall, totalBytesExpectedToSend)`. Order and eventual
        /// completion are what's guaranteed -- individual chunk sizes are URLSession's own to
        /// pick, not RequestDL's.
        package func execute<Body: AsyncSequence & Sendable>(
            request: URLRequest,
            streaming body: Body,
            delegate: URLSessionTaskDelegate? = nil,
            existingUploadFile: URL? = nil,
            onUploadProgress: (@Sendable (Int, Int) -> Void)? = nil
        ) async throws -> (head: Internals.ResponseHead, body: Data) where Body.Element == ByteBuffer {
            let release = await throttledExecutor.acquire()
            defer { release() }

            let operation = operationQueue.operation()
            defer { operation.complete() }

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
                initialURL: request.url?.absoluteString ?? "",
                proxyAuthorization: proxyAuthorization,
                tls: tlsDelegate,
                forwarding: delegate,
                onUploadProgress: onUploadProgress
            )

            do {
                let result = try await withCheckedThrowingContinuation { continuation in
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
                    task.resume()
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
        /// `Internals.DownloadBuffer` -- the same type `Internals.Session.execute(...)` builds for
        /// the NIO path, reused verbatim here rather than reimplemented, since it already has no
        /// NIO dependency of its own (it consumes `Internals.AnyBuffer`, not `ByteBuffer`
        /// directly).
        ///
        /// Unlike the other two `execute` overloads, the throttle slot acquired at the top is
        /// *not* released when this method returns -- it has to stay held until the download
        /// itself finishes, which happens well after this `async` call returns its
        /// `Internals.DownloadStep`. `TaskDelegate` releases it from
        /// `urlSession(_:task:didCompleteWithError:)` instead.
        package func execute(
            request: URLRequest,
            readingMode: Internals.DownloadStep.ReadingMode,
            delegate: URLSessionTaskDelegate? = nil
        ) async throws -> Internals.DownloadStep {
            let release = await throttledExecutor.acquire()
            let operation = operationQueue.operation()

            let tlsDelegate = identityPolicy.flatMap { policy in
                request.url?.host.map { TLSDelegate(host: $0, policy: policy) }
            }

            // Built here, in an `async` context that can freely `await`, rather than inside a
            // synchronous delegate callback -- `Internals.DownloadBuffer.init(readingMode:)` is
            // itself `async`, and `didReceive response:completionHandler:` below has no way to
            // await it without risking `didReceive data:` firing (URLSession serializes delegate
            // callbacks for one task, but only across calls that have themselves returned) before
            // a detached `Task` doing so had a chance to finish.
            let downloadBuffer = await Internals.DownloadBuffer(readingMode: readingMode)

            let taskDelegate = TaskDelegate(
                redirectConfiguration: redirectConfiguration,
                initialURL: request.url?.absoluteString ?? "",
                proxyAuthorization: proxyAuthorization,
                tls: tlsDelegate,
                forwarding: delegate,
                downloadBuffer: downloadBuffer,
                onDownloadComplete: {
                    release()
                    operation.complete()
                }
            )

            return try await withCheckedThrowingContinuation { continuation in
                taskDelegate.headCompletion = { continuation.resume(with: $0) }

                let task = session.dataTask(with: request)
                task.delegate = taskDelegate
                task.resume()
            }
        }

        /// Executes `request`, returning a `SessionTask` whose response streams upload progress
        /// (when `request` carries a body), the response head, and the body -- optionally teed
        /// to `cache` as it downloads.
        ///
        /// Mirrors `Internals.Client.execute(request:url:readingMode:uploadingBytes:cache:logger:)`:
        /// gives `RequestExecutingClient`'s `.urlSession` conformance the same three
        /// independent `Internals.AsyncStream`s (`upload`/`head`/`download`) to build an
        /// `Internals.AsyncResponse` from that the NIO backend already produces, just fed by this
        /// client's own callbacks instead of `Internals.ClientResponseReceiver`'s.
        ///
        /// No new delegate machinery -- reuses the exact `headCompletion`/`downloadBuffer`
        /// mechanism `execute(request:readingMode:delegate:)` already has below, just resolving
        /// into these three streams instead of a continuation. The cache tee
        /// (`Internals.DownloadBuffer.cacheStream(_:)`) attaches from right here, at the same
        /// point `Internals.ClientResponseReceiver.didReceiveHead` attaches it on the NIO side --
        /// before any body chunk can arrive, since `didReceive response:completionHandler:`
        /// always precedes `didReceive data:`.
        package func execute(
            request: URLRequest,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            delegate: URLSessionTaskDelegate? = nil
        ) async throws -> SessionTask {
            try await executeSessionTask(
                request: request,
                readingMode: readingMode,
                uploadingBytes: uploadingBytes,
                cache: cache,
                logger: logger,
                forwarding: delegate,
                makeUploadBody: nil
            )
        }

        /// Combines what `execute(request:streaming:delegate:onUploadProgress:)` and
        /// `execute(request:readingMode:delegate:)` each build separately -- a genuinely streamed
        /// request body *and* a genuinely streamed response, at once.
        ///
        /// `TaskDelegate` already implements both `needNewBodyStream`/`didSendBodyData` and
        /// `didReceive response:`/`didReceive data:` unconditionally -- this is the first call
        /// site that activates both sets of optional fields on the same task, not new delegate
        /// logic. See `execute(request:readingMode:uploadingBytes:cache:logger:)` just above for
        /// everything else (the three-stream `SessionTask` shape, the cache tee).
        /// - Parameter existingUploadFile: See the standalone streaming `execute`'s doc comment
        /// for this same parameter -- identical meaning here, `body` still required but unread
        /// when set.
        package func execute<Body: AsyncSequence & Sendable>(
            request: URLRequest,
            streaming body: Body,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            delegate: URLSessionTaskDelegate? = nil,
            existingUploadFile: URL? = nil
        ) async throws -> SessionTask where Body.Element == ByteBuffer {
            try await executeSessionTask(
                request: request,
                readingMode: readingMode,
                uploadingBytes: uploadingBytes,
                cache: cache,
                logger: logger,
                forwarding: delegate,
                makeUploadBody: {
                    if let existingUploadFile {
                        return .existingFile(existingUploadFile)
                    }
                    return try await Internals.URLSessionUploadFile.write(body: body)
                }
            )
        }

        /// Shared body for the two `SessionTask`-producing `execute` overloads above -- they
        /// differ only in whether a body needs materializing first (`makeUploadBody`, `nil` for
        /// the no-body/non-streaming case), which in turn decides whether this builds a
        /// `dataTask(with:)`, an `uploadTask(with:from:)`, or an `uploadTask(with:fromFile:)`. See
        /// `execute(request:streaming:delegate:onUploadProgress:)`'s doc comment for why neither
        /// upload shape streams through an `InputStream`.
        private func executeSessionTask(
            request: URLRequest,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            forwarding delegate: URLSessionTaskDelegate?,
            makeUploadBody: (@Sendable () async throws -> Internals.URLSessionUploadFile.Materialized)?
        ) async throws -> SessionTask {
            let release = await throttledExecutor.acquire()
            let operation = operationQueue.operation()

            let uploadBody: Internals.URLSessionUploadFile.Materialized?
            do {
                uploadBody = try await makeUploadBody?()
            } catch {
                release()
                operation.complete()
                throw error
            }

            let tlsDelegate = identityPolicy.flatMap { policy in
                request.url?.host.map { TLSDelegate(host: $0, policy: policy) }
            }

            let upload = Internals.AsyncStream<Int>()
            let head = Internals.AsyncStream<Internals.ResponseHead>()
            let downloadBuffer = await Internals.DownloadBuffer(readingMode: readingMode)

            let taskDelegate = TaskDelegate(
                redirectConfiguration: redirectConfiguration,
                initialURL: request.url?.absoluteString ?? "",
                proxyAuthorization: proxyAuthorization,
                tls: tlsDelegate,
                forwarding: delegate,
                onUploadProgress: { bytesSent, _ in
                    upload.append(.success(bytesSent))
                },
                downloadBuffer: downloadBuffer,
                onDownloadComplete: {
                    upload.close()
                    release()
                    operation.complete()
                    if case .file(let bufferURL) = uploadBody {
                        Task { await bufferURL.removeIfTemporary() }
                    }
                }
            )

            // Set before `task.resume()`, same ordering `execute(request:readingMode:delegate:)`
            // already relies on, so no callback can fire before this closure is in place.
            taskDelegate.headCompletion = { result in
                // A response head -- success or failure -- can only exist once the request body
                // finished sending, so this is also where `upload` closes: mirrors
                // `Internals.ClientResponseReceiver.didReceiveHead`, which closes `upload` again
                // here too even though `didSendRequest` already closed it once, redundantly and
                // harmlessly (`Internals.AsyncStream.close()` is idempotent) -- `onDownloadComplete`
                // below closes it a third time for the same reason: any path that reaches the end
                // must leave `upload` closed, not just the common one.
                upload.close()

                switch result {
                case .success(let step):
                    // Attached before `head` is ever read from -- ordered against every future
                    // `downloadBuffer.append(_:)` by `Internals.DownloadBuffer`'s own queue, the
                    // same guarantee `Internals.ClientResponseReceiver.didReceiveHead` relies on.
                    if let cacheStream = cache?(step.head) {
                        downloadBuffer.cacheStream(cacheStream)
                    }
                    head.append(.success(step.head))
                case .failure(let error):
                    head.append(.failure(error))
                }
                head.close()
            }

            let task: URLSessionTask
            switch uploadBody {
            case .data(let data):
                task = session.uploadTask(with: request, from: data)
            case .file(let bufferURL):
                task = session.uploadTask(with: request, fromFile: bufferURL.absoluteURL())
            case .existingFile(let url):
                task = session.uploadTask(with: request, fromFile: url)
            case nil:
                task = session.dataTask(with: request)
            }
            task.delegate = taskDelegate
            task.resume()

            let response = Internals.AsyncResponse(
                logger: logger,
                uploadingBytes: uploadingBytes,
                upload: upload,
                head: head,
                download: downloadBuffer.stream
            )

            return SessionTask(
                seed: Internals.TaskSeed { task.cancel() },
                response: response
            )
        }

        /// Invalidates the underlying `URLSession` -- mirrors `Internals.Client.shutdown()`, read
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

            // No outstanding tasks per the `isRunning` guard above, so there is nothing to drain
            // -- unlike `HTTPClient.shutdown()`, invalidation here is immediate, not awaited.
            session.invalidateAndCancel()
            return true
        }
    }
}

extension Internals.URLSessionClient {

    /// `URLSession` only ever hands back a non-`HTTPURLResponse` for a non-HTTP(S) scheme, which
    /// RequestDL never builds a request for -- this should be unreachable in practice.
    package struct UnexpectedURLResponseError: Error, Sendable {
        package let response: URLResponse
    }

    /// A streamed-upload task (`execute(request:streaming:delegate:onUploadProgress:)`) completed
    /// with no error and yet never called `urlSession(_:dataTask:didReceive:completionHandler:)`
    /// -- should be unreachable given `URLSession`'s own contract (every task either fails or
    /// eventually receives a response), kept as a named error rather than force-unwrapping.
    package struct MissingURLResponseError: Error, Sendable {}

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
    /// `onCancel` can fire the instant cancellation is requested -- including strictly before
    /// `operation` ever assigns `task` -- so a plain `URLSessionTask?` written to after the fact
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
/// authentication, and -- when this client was built with a `secureConnection` -- TLS challenge
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
        /// Set for the streamed-download `execute(request:readingMode:delegate:)` path only --
        /// `nil` for the other two, which is exactly the switch `didReceive
        /// response:completionHandler:`/`didReceive data:`/`didCompleteWithError:` use below to
        /// tell which of the three modes this instance is answering for.
        private let downloadBuffer: Internals.DownloadBuffer?
        /// Releases the throttle slot `execute(request:readingMode:delegate:)` acquired -- see
        /// that method's own doc comment for why it can't just `defer { release() }` the way the
        /// other two `execute` overloads do.
        private let onDownloadComplete: (@Sendable () -> Void)?
        private let lock = Lock()

        // MARK: - Unsafe properties

        /// All visited URLs, starting with the request's own -- mirrors `RedirectState.visited`.
        private var _visited: [String]
        private var _redirectError: Error?
        /// Response accumulation for the streamed-upload path only -- the buffered path never
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
        /// a response ever arrives, from `didCompleteWithError:` instead -- guarded by `_headResolved`
        /// so whichever fires first wins and the other is a no-op.
        private var _headCompletion: ((Result<Internals.DownloadStep, Error>) -> Void)?
        private var _headResolved = false

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
            initialURL: String,
            proxyAuthorization: Internals.Proxy.Authorization?,
            tls tlsDelegate: TLSDelegate?,
            forwarding delegate: URLSessionTaskDelegate?,
            onUploadProgress: (@Sendable (Int, Int) -> Void)? = nil,
            downloadBuffer: Internals.DownloadBuffer? = nil,
            onDownloadComplete: (@Sendable () -> Void)? = nil
        ) {
            self.redirectConfiguration = redirectConfiguration
            self.proxyAuthorization = proxyAuthorization
            self.tlsDelegate = tlsDelegate
            self.forwardingDelegate = delegate
            self.onUploadProgress = onUploadProgress
            self.downloadBuffer = downloadBuffer
            self.onDownloadComplete = onDownloadComplete
            self._visited = [initialURL]
            self._responseData = Data()
        }

        // MARK: - Internal methods

        /// Enforces `Internals.RedirectConfiguration` for this task.
        ///
        /// URLSession has no native "max redirects" / "allow cycles" concept --
        /// `willPerformHTTPRedirection` only ever offers "follow this exact request" or "don't,
        /// and treat the redirect response as final." Both the counting and the cycle detection
        /// below are a direct port of what AsyncHTTPClient's own `RedirectState`
        /// (`RedirectState.swift`, vendored in `async-http-client`) does for the NIO executor, so
        /// the two backends fail identically for the same configuration.
        ///
        /// `.disallow` needs no tracking at all: every redirect is refused via
        /// `completionHandler(nil)`, same as AsyncHTTPClient handing back the 3xx response
        /// untouched when `redirectHandler` is `nil` -- not a `redirectError`, since declining to
        /// follow is not itself a failure.
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard case .follow(let max, let allowCycles) = redirectConfiguration else {
                completionHandler(nil)
                return
            }

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
                completionHandler(request)
            case .failure(let error):
                lock.withLock { _redirectError = error }
                completionHandler(nil)
            }
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
                completionHandler(.useCredential, credential)
                return
            }

            if let tlsDelegate {
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

        /// Response-side counterpart to `needNewBodyStream` above -- exercised by the
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

            // Sync, deliberately -- `Internals.DownloadBuffer.append(_:)` enqueues onto an
            // ordered queue, and submission order has to match arrival order. Building the
            // `Internals.DataBuffer` on a detached `Task` (its usual, `async`, in-memory-or-file
            // generic initializer) would let two chunks race to enqueue and reassemble the body
            // out of order -- `Internals.Buffer`'s own "Synchronous construction, in memory only"
            // extension exists for precisely this reason (see its doc comment, which calls out a
            // NIO delegate callback as the original motivating case; this is the same shape of
            // problem one layer up, for `URLSessionDataDelegate` instead of
            // `HTTPClientResponseDelegate`).
            let byteURL = Internals.ByteURL(ByteBuffer(bytes: data))
            downloadBuffer.append(Internals.DataBuffer(byteURL))
        }

        /// Resolves `completion`/`headCompletion` -- the streamed-upload and streamed-download
        /// paths' only way to learn a task is done, since neither goes through
        /// `session.data(for:delegate:)`'s own `async` completion. A no-op for the buffered path,
        /// where `completion` is never set.
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let downloadBuffer {
                defer { onDownloadComplete?() }

                // A failure before any response ever arrived (e.g. connection refused) means
                // `didReceive response:` never ran and `headCompletion` is still unresolved --
                // resolve it now rather than leaving `execute(request:readingMode:delegate:)`
                // suspended forever. `resolveHead(with:downloadBuffer:)` is a no-op if a response
                // already resolved it, so this is safe to call unconditionally.
                if let error {
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
                completion(.failure(error))
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

        /// Resolves `headCompletion` from the response URLSession actually delivered --
        /// `didReceive response:completionHandler:`'s normal path. A no-op if `headCompletion`
        /// already resolved (guarded by `_headResolved`), which only happens if
        /// `didCompleteWithError:` beat it to a failure -- shouldn't happen given `URLSession`'s
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

        /// Resolves `headCompletion` with `error` -- only actually resolves anything if no
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

        /// `.basic`/`.basicRawCredentials` only -- `URLCredential` has exactly two shapes
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

extension Internals.ResponseHead {

    init(_ response: HTTPURLResponse) {
        self.init(
            url: response.url?.absoluteString ?? "",
            status: Status(
                code: UInt(response.statusCode),
                reason: HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            ),
            // `HTTPURLResponse` does not expose the negotiated HTTP version -- only
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
            // Not observable per response over URLSession -- connection reuse is entirely
            // internal to the session. `true` matches HTTP/1.1's own default.
            isKeepAlive: true
        )
    }
}

#endif
