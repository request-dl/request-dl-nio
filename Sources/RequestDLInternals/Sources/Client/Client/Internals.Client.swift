//
// See LICENSE for this package's licensing information.
//

// Entirely NIO-only: this is the AsyncHTTPClient-backed client for the .nio/.nioTransportServices
// executors. .urlSession has its own separate implementation, Internals.URLSessionClient, which
// imports none of this.
#if canImport(NIOCore)

import AsyncHTTPClient
import Logging
import NIOCore
import SwiftAsyncStream

extension Internals {

    package final class Client: @unchecked Sendable {

        // MARK: - Internal properties

        package var isRunning: Bool {
            manager.isRunning
        }

        /// Mirrors `Internals.ClientOperationQueue.generation`, read by
        /// `Internals.ClientManager`'s idle-cleanup sweep and ceiling eviction alongside
        /// `isRunning` -- see that property's own doc comment.
        package var operationGeneration: UInt64 {
            manager.generation
        }

        // MARK: - Internal properties

        /// The group this client runs on.
        ///
        /// Exposed so a request body can be streamed from a loop this client already owns,
        /// rather than from one derived by writing a zero length chunk down the wire just to
        /// get hold of a future. See `RequestBody.connect(writer:body:eventLoop:)`.
        package var eventLoopGroup: EventLoopGroup {
            _client.eventLoopGroup
        }

        // MARK: - Private static properties

        /// Flags a `shutdown()` that is still running after 20s: draining real, in-flight
        /// connections can legitimately take a few seconds under load, longer than the other
        /// `AsyncLock`s in `Internals`. Development builds only. See `AsyncLock.Watchdog`.
        #if DEBUG
        private static let watchdog: AsyncLock.Watchdog? = .init(seconds: 20) {
            Internals.assertionFailure($0)
        }
        #else
        private static let watchdog: AsyncLock.Watchdog? = nil
        #endif

        // MARK: - Private properties

        private let lock = AsyncLock(watchdog: watchdog)

        private let manager = Internals.ClientOperationQueue()
        private let _client: HTTPClient

        /// Keeps the event-loop group this client runs on alive for at least as long as the
        /// client itself.
        ///
        /// `HTTPClient.EventLoopGroupProvider.shared(_:)` means the client does *not* own the
        /// group, and `Internals.EventLoopGroupManager`'s table is a cache that can drop its own
        /// reference at any point. Without this, a group could be retired while this client still
        /// had requests on it — and a client whose loops are gone can never complete its own
        /// `shutdown()`, which NIO traps on as a leaked promise. `nil` only where no manager was
        /// involved (tests constructing a client directly).
        private let eventLoopGroupToken: Internals.EventLoopGroupToken?

        /// Caps how many requests this client may have in flight at once, from the moment a
        /// request is asked to execute until it completes, is cancelled, or is released.
        private let throttledExecutor: Internals.ThrottledExecutor

        #if canImport(Darwin)
        /// The mTLS client identity's Keychain-item handle, when `SecureConnection.certificateChain`/
        /// `.privateKey` were configured for a Network.framework connection. Held for as long as
        /// this `Client` (and so this client's underlying `HTTPClient`) is alive.
        ///
        /// Released automatically through `IdentityHandle`'s own `deinit` once this property is
        /// torn down, mirroring `Internals.URLSessionIdentityPolicy`'s own identity lifecycle
        /// exactly, and only actually deleting the underlying Keychain items once every other
        /// live `Internals.IdentityHandle` for that same certificate/key pair has gone away too.
        private let localIdentityHandle: Internals.IdentityHandle?
        #endif

        // MARK: - Unsafe properties

        private var _isClosed: Bool

        // MARK: - Inits

        // Swift doesn't reliably parse a parameter conditionally included in the middle of a
        // parameter list (as opposed to a whole declaration), so this is two complete inits
        // rather than one with a `#if`-guarded parameter.
        #if canImport(Darwin)
        package init(
            eventLoopGroupProvider: HTTPClient.EventLoopGroupProvider,
            configuration: HTTPClient.Configuration,
            localIdentityHandle: Internals.IdentityHandle? = nil,
            maximumConcurrentConnections: Int? = nil,
            eventLoopGroupToken: Internals.EventLoopGroupToken? = nil
        ) {
            _isClosed = false
            _client = .init(
                eventLoopGroupProvider: eventLoopGroupProvider,
                configuration: configuration
            )
            throttledExecutor = Internals.ThrottledExecutor(
                maximumConcurrentConnections: maximumConcurrentConnections
            )
            self.localIdentityHandle = localIdentityHandle
            self.eventLoopGroupToken = eventLoopGroupToken
        }
        #else
        package init(
            eventLoopGroupProvider: HTTPClient.EventLoopGroupProvider,
            configuration: HTTPClient.Configuration,
            maximumConcurrentConnections: Int? = nil,
            eventLoopGroupToken: Internals.EventLoopGroupToken? = nil
        ) {
            _isClosed = false
            _client = .init(
                eventLoopGroupProvider: eventLoopGroupProvider,
                configuration: configuration
            )
            throttledExecutor = Internals.ThrottledExecutor(
                maximumConcurrentConnections: maximumConcurrentConnections
            )
            self.eventLoopGroupToken = eventLoopGroupToken
        }
        #endif

        deinit {
            // The mTLS identity's Keychain items (if any) are released through
            // `localIdentityHandle`'s own `deinit`, automatically, once this stored property is
            // torn down below. No explicit call needed here.

            // Shutting down from here is a last resort, so it is guarded by the same flag the
            // explicit path sets. Without the guard this shut down a client the manager had
            // already closed, and the second call is an error nobody was positioned to see.
            //
            // The client is captured, not `self`, and the task keeps it alive until the
            // shutdown finishes, so it is never released mid shutdown.
            //
            // `eventLoopGroupToken` is captured for the same reason: this stored property is
            // released as soon as this body returns, and a group retired while `shutdown()` is
            // still running leaves that shutdown's promise unfulfillable, which NIO traps on.
            guard !_isClosed else {
                return
            }

            _Concurrency.Task { [_client, eventLoopGroupToken] in
                try? await _client.shutdown()
                _ = eventLoopGroupToken
            }
        }

        // MARK: - Internal methods

        package func execute(
            request: HTTPClient.Request,
            logger: TaskLogger?
        ) async throws -> UnsafeTask<ResponseAccumulator.Response> {
            try await execute(
                request: request,
                delegate: ResponseAccumulator(request: request),
                logger: logger
            )
        }

        package func execute<Delegate: HTTPClientResponseDelegate>(
            request: HTTPClient.Request,
            delegate: Delegate,
            logger: TaskLogger?
        ) async throws -> UnsafeTask<Delegate.Response> {
            // Waited on before anything else, so a session configured with a limit never opens
            // more connections than that, whether or not one is free to reuse.
            let release = await throttledExecutor.acquire()

            // `AsyncSemaphore.wait()` (backing `acquire()` above) is documented as "cancellation
            // transparent": a waiter cancelled while queued still takes its turn once a slot
            // frees up, rather than being skipped. Without this check, a caller whose own `Task`
            // was cancelled while queued here still had its request dispatched onto the wire the
            // moment `acquire()` returned. The slot is handed back first, since it was already
            // claimed and nothing past this point will release it otherwise.
            guard !Task.isCancelled else {
                release()
                throw CancellationError()
            }

            // Registered before the request goes out, so the client counts as busy from the
            // moment it is asked to do anything.
            let operation = manager.operation()

            let task: HTTPClient.Task<Delegate.Response>

            if let logger {
                task = _client.execute(
                    request: request,
                    delegate: delegate,
                    logger: logger.logger
                )
            } else {
                task = _client.execute(
                    request: request,
                    delegate: delegate
                )
            }

            return UnsafeTask(task) {
                // No lock and no task hop. Completing an operation is a counter decrement now,
                // so wrapping it in `AsyncLock` only bought a suspension on a path that can be
                // reached from an event loop.
                operation.complete()
                release()
            }
        }

        /// Executes `request`, streaming the response through a `SessionTask`: upload
        /// progress, head, and body, optionally teed to `cache` as it downloads.
        ///
        /// Moved here from `Internals.Session.execute(client:request:...)`: that method's body
        /// never actually touched `Internals.Session` itself (`provider`/`configuration`/
        /// `manager`), just the `client` it took as a parameter, so it belongs on the client that
        /// does the executing. `Internals.Session.execute` now forwards here rather than
        /// duplicating this body, so its three existing direct callers (`SessionExecutionTests`,
        /// `LocalServerConcurrencyTests`, `InternalsClientResponseReceiverTests`) keep working
        /// unmodified.
        ///
        /// - Parameter flowControl: What `delegate` consults before letting AsyncHTTPClient read
        ///   more of the body, so the network can't run arbitrarily far ahead of whoever is
        ///   reading. See `Internals.ClientResponseReceiver.didReceiveBodyPart(task:_:)`. A fresh
        ///   window with the default watermarks per request; only tests pass their own, to pin
        ///   the pause down to an exact byte.
        /// - Parameter transferControl: Suspends and resumes this execution, and reconnects its
        ///   download if the connection is lost (see `Internals.TransferControl`). `nil` behaves
        ///   exactly as before it existed. Suspending the *request body* additionally needs
        ///   `request`'s body to stream through `Internals.StreamWriterSequence` with this
        ///   control's `gate` (see `RequestBody.build(eventLoop:gate:)`): the body is built
        ///   before it gets here.
        package func execute(
            request: HTTPClient.Request,
            url: String,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            decompression: Internals.Decompression,
            cache: ((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: TaskLogger?,
            flowControl: Internals.FlowControlWindow = .init(),
            transferControl: Internals.TransferControl? = nil
        ) async throws -> SessionTask {
            // Before anything can be produced into the window, so a suspension that came first
            // already holds.
            transferControl?.attach(flowControl)

            let upload = Internals.AsyncStream<Int>()
            let head = Internals.AsyncStream<Internals.ResponseHead>()
            let download = await Internals.DownloadBuffer(readingMode: readingMode, flowControl: flowControl)

            // Only a bodyless request can be continued with `Range` (and only a `GET`, which
            // `Internals.RangeResumptionPlan` checks once the head is in): a streamed body can't
            // be sent again.
            let reconnection = transferControl.flatMap { transferControl in
                transferControl.resumption.flatMap { policy -> NIODownloadReconnection? in
                    guard request.body == nil else {
                        return nil
                    }

                    return NIODownloadReconnection(
                        client: self,
                        request: request,
                        url: url,
                        download: download,
                        flowControl: flowControl,
                        transferControl: transferControl,
                        policy: policy,
                        logger: logger
                    )
                }
            }

            // No all-or-nothing constraint on this executor, unlike `.urlSession`: manual
            // dispatch only has to activate for algorithms `NIOHTTPResponseDecompressor` (added
            // separately, once, via `Internals.Session.Configuration.build()`) doesn't already
            // handle: gzip/deflate can stay skipped alongside it, rather than every configured
            // algorithm always going through manual dispatch regardless.
            //
            // - Important: `NIOHTTPResponseDecompressor` decodes the body but does *not* strip
            // `Content-Encoding` from the response head (confirmed against the vendored
            // `swift-nio-extras` source this package actually ships), the same caveat already
            // documented for CFNetwork's own transparent decoding under `.urlSession`.
            //
            // Dispatch must therefore bypass by *type* (`isNativelyDecodedByNIO`), the same
            // structural check `Internals.URLSessionClient` uses, not by checking whether the
            // header is still present: it always is, natively decoded or not.
            //
            // A *mixed* list (say gzip plus a custom algorithm) is what makes
            // `nativelyDecoded` necessary rather than merely tidy. `Internals.Decompression
            // .build()` enables `NIOHTTPResponseDecompressor` as soon as any one algorithm is
            // natively decoded, so a `Content-Encoding: gzip` response arrives already decoded —
            // and, per the note above, still labelled. Handing the full list to manual dispatch
            // then matched gzip a second time and decoded the body twice.
            //
            // Filtering the natives out of the list isn't enough on its own: that turns the
            // double decode into an `UnsupportedContentEncodingError` for a response that was in
            // fact decoded correctly. What manual dispatch needs to know is which encodings to
            // leave alone, not merely which algorithms it owns.
            let decompressionDispatch: Internals.ManualDecompressionDispatch = {
                switch decompression {
                case .disabled:
                    return .skip
                case .enabled(let algorithms, _) where !algorithms.allSatisfy(\.isNativelyDecodedByNIO):
                    return .dispatch(
                        algorithms: algorithms.filter { !$0.isNativelyDecodedByNIO },
                        nativelyDecoded: Set(
                            algorithms
                                .filter(\.isNativelyDecodedByNIO)
                                .map { $0.contentEncodingValue.lowercased() }
                        )
                    )
                case .enabled:
                    return .skip
                }
            }()

            let delegate = Internals.ClientResponseReceiver(
                url: url,
                upload: upload,
                head: head,
                download: download,
                cache: cache,
                decompressionDispatch: decompressionDispatch,
                logger: logger,
                transferControl: transferControl,
                reconnection: reconnection
            )

            let response = Internals.AsyncResponse(
                logger: logger,
                uploadingBytes: uploadingBytes,
                upload: upload,
                decompressionDispatch: decompressionDispatch,
                head: head,
                download: download.stream
            )

            let unsafeTask = try await execute(
                request: request,
                delegate: delegate,
                logger: logger
            )

            // A pre-flight rejection (`HTTPClient.Task.failedTask`, e.g. for
            // `.invalidRedirectConfiguration`/`.alreadyShutdown`) resolves `unsafeTask`'s own
            // response without ever calling `delegate`, so `head`/`upload`/`download` would
            // otherwise never close and `response` would hang forever. Observing the task here
            // and forwarding any such failure closes that gap; it is a no-op whenever the
            // delegate was actually driven, since `failIfNotStarted` only acts while it is still
            // untouched.
            //
            // - Important: Through `whenFailure`, not a `Task` awaiting `unsafeTask.response()`.
            // That `Task` captured `unsafeTask`, and with it the request's `TaskSeed`, for as long
            // as the request ran, so the seed could never deinit when the caller dropped the
            // response: a `break` out of a body stream, or an abandoned endless stream, kept
            // downloading into a buffer nobody read, and kept its connection and throttle permit.
            unsafeTask.whenFailure { error in
                delegate.failIfNotStarted(error)
            }

            // Cancelling or dropping the response has to release `flowControl` itself, and not
            // rely on the cancellation reaching `delegate.didReceiveError` to do it.
            //
            // AsyncHTTPClient only reports a failure straight away while it still has more of
            // the body to read. Once the response's end has already arrived -- sitting in its
            // own buffer behind a body part whose future is waiting on this window -- a
            // cancellation only discards that buffer and records the error, to be delivered
            // after that future completes (`RequestBag.StateMachine.fail(_:)`, the
            // `.buffering(_, next: .eof)` case). With a reader that is gone, or that stopped for
            // good, that future never would: the `HTTPClient.Task` would never complete, and the
            // request, its delegate and whatever it buffered would stay reachable from the pending
            // promise's own callbacks indefinitely. Observed directly, not inferred; see
            // `InternalsClientResponseReceiverBackPressureTests
            // .requestCancelledAfterTheEndAlreadyArrived_stillReleasesThePausedPart`.
            //
            // The order relative to the request's own seed doesn't matter. Releasing lets
            // AsyncHTTPClient resume consuming whatever it had buffered, which is harmless either
            // way: at worst the request finishes normally a moment before the cancellation lands,
            // and `UnsafeTask` orders those two on the event loop.
            //
            // A suspension is released the same way (`transferControl`'s gate), and so is a
            // download continuing on another exchange: `reconnection` cancels whichever
            // continuation is running, or ends the body if it's between two.
            let requestSeed = unsafeTask()

            let seed = Internals.TaskSeed(
                cancel: {
                    requestSeed()
                    reconnection?.cancel()
                    flowControl.release()
                    transferControl?.release()
                },
                release: {
                    // `requestSeed`'s own `deinit`, which is what cancels a dropped request, runs
                    // once this closure -- its last owner -- goes away with the seed wrapping it.
                    withExtendedLifetime(requestSeed) {
                        reconnection?.cancel()
                        flowControl.release()
                        transferControl?.release()
                    }
                }
            )

            return SessionTask(
                seed: seed,
                response: response
            )
        }

        /// Counts this client as busy until the returned operation completes (or is released),
        /// independently of any request actually being on the wire.
        ///
        /// For a download waiting to reconnect (`Internals.NIODownloadReconnection`): between
        /// two exchanges nothing is in flight, possibly for as long as the execution stays
        /// suspended, and `Internals.ClientManager`'s idle sweep would otherwise be free to shut
        /// this client down under the reconnection about to use it.
        package func holdOperation() -> Internals.ClientOperation {
            manager.operation()
        }

        package func shutdown() async throws -> Bool {
            try await lock.withLock {
                guard !isRunning && !_isClosed else {
                    return false
                }

                try await _client.shutdown()
                _isClosed = true
                return true
            }
        }
    }
}

// MARK: - Testing

@_spi(Testing)
extension Internals.Client {

    /// The semaphore backing `maximumConcurrentConnections`, `nil` when the client was not
    /// configured with a limit.
    ///
    /// Forwards to `throttledExecutor`'s own testing accessor: the semaphore itself moved
    /// there so `maximumConcurrentConnections` behaves identically across executors, but this
    /// accessor's name and gating stay put so the tests reaching for it don't have to change.
    /// Gated behind `@_spi(Testing)` on top of `package` so this reads as a deliberate escape
    /// hatch and not something ordinary package code reaches for by accident. Exposed so a test
    /// can wait for an exact ``AsyncSemaphore/waitingCount`` instead of sleeping a fixed duration
    /// and hoping the right number of requests reached the semaphore by then: sleep-based
    /// synchronization races under CI scheduler contention the same way `AsyncLock.Watchdog`
    /// false positives do.
    public var connectionSemaphoreForTesting: AsyncSemaphore? {
        throttledExecutor.semaphoreForTesting
    }
}

#endif
