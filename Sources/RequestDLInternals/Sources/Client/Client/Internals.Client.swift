//
// See LICENSE for this package's licensing information.
//

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

        /// Flags a `shutdown()` that is still running after 20s — draining real, in-flight
        /// connections can legitimately take a few seconds under load, longer than the other
        /// `AsyncLock`s in `Internals`. Development builds only — see `AsyncLock.Watchdog`.
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

        /// Caps how many requests this client may have in flight at once, from the moment a
        /// request is asked to execute until it completes, is cancelled, or is released.
        private let throttledExecutor: Internals.ThrottledExecutor

        // MARK: - Unsafe properties

        private var _isClosed: Bool

        // MARK: - Inits

        package init(
            eventLoopGroupProvider: HTTPClient.EventLoopGroupProvider,
            configuration: HTTPClient.Configuration,
            maximumConcurrentConnections: Int? = nil
        ) {
            _isClosed = false
            _client = .init(
                eventLoopGroupProvider: eventLoopGroupProvider,
                configuration: configuration
            )
            throttledExecutor = Internals.ThrottledExecutor(
                maximumConcurrentConnections: maximumConcurrentConnections
            )
        }

        deinit {
            // Shutting down from here is a last resort, so it is guarded by the same flag the
            // explicit path sets. Without the guard this shut down a client the manager had
            // already closed, and the second call is an error nobody was positioned to see.
            //
            // The client is captured, not `self`, and the task keeps it alive until the
            // shutdown finishes, so it is never released mid shutdown.
            guard !_isClosed else {
                return
            }

            _Concurrency.Task { [_client] in
                try? await _client.shutdown()
            }
        }

        // MARK: - Internal methods

        package func execute(
            request: HTTPClient.Request,
            logger: TaskLogger?
        ) async -> UnsafeTask<ResponseAccumulator.Response> {
            await execute(
                request: request,
                delegate: ResponseAccumulator(request: request),
                logger: logger
            )
        }

        package func execute<Delegate: HTTPClientResponseDelegate>(
            request: HTTPClient.Request,
            delegate: Delegate,
            logger: TaskLogger?
        ) async -> UnsafeTask<Delegate.Response> {
            // Waited on before anything else, so a session configured with a limit never opens
            // more connections than that, whether or not one is free to reuse.
            let release = await throttledExecutor.acquire()

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

        /// Executes `request`, streaming the response through a `SessionTask` -- upload
        /// progress, head, and body, optionally teed to `cache` as it downloads.
        ///
        /// Moved here from `Internals.Session.execute(client:request:...)` -- that method's body
        /// never actually touched `Internals.Session` itself (`provider`/`configuration`/
        /// `manager`), just the `client` it took as a parameter, so it belongs on the client that
        /// does the executing. `Internals.Session.execute` now forwards here rather than
        /// duplicating this body, so its three existing direct callers (`SessionExecutionTests`,
        /// `LocalServerConcurrencyTests`, `InternalsClientResponseReceiverTests`) keep working
        /// unmodified.
        package func execute(
            request: HTTPClient.Request,
            url: String,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            cache: ((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: TaskLogger?
        ) async throws -> SessionTask {
            let upload = Internals.AsyncStream<Int>()
            let head = Internals.AsyncStream<Internals.ResponseHead>()
            let download = await Internals.DownloadBuffer(readingMode: readingMode)

            let delegate = Internals.ClientResponseReceiver(
                url: url,
                upload: upload,
                head: head,
                download: download,
                cache: cache,
                logger: logger
            )

            let response = Internals.AsyncResponse(
                logger: logger,
                uploadingBytes: uploadingBytes,
                upload: upload,
                head: head,
                download: download.stream
            )

            let unsafeTask = await execute(
                request: request,
                delegate: delegate,
                logger: logger
            )

            return SessionTask(
                seed: unsafeTask(),
                response: response
            )
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
