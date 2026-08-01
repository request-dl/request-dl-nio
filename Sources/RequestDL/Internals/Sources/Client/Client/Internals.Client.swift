//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Logging
import NIOCore
import SwiftAsyncStream

extension Internals {

    final class Client: @unchecked Sendable {

        // MARK: - Internal properties

        var isRunning: Bool {
            manager.isRunning
        }

        // MARK: - Private properties

        private let lock = AsyncLock()

        private let manager = Internals.ClientOperationQueue()
        private let _client: HTTPClient

        // MARK: - Unsafe properties

        private var _isClosed: Bool

        // MARK: - Inits

        init(
            eventLoopGroupProvider: HTTPClient.EventLoopGroupProvider,
            configuration: HTTPClient.Configuration
        ) {
            _isClosed = false
            _client = .init(
                eventLoopGroupProvider: eventLoopGroupProvider,
                configuration: configuration
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

        func execute(
            request: HTTPClient.Request,
            logger: TaskLogger?
        ) -> UnsafeTask<ResponseAccumulator.Response> {
            execute(
                request: request,
                delegate: ResponseAccumulator(request: request),
                logger: logger
            )
        }

        func execute<Delegate: HTTPClientResponseDelegate>(
            request: HTTPClient.Request,
            delegate: Delegate,
            logger: TaskLogger?
        ) -> UnsafeTask<Delegate.Response> {
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
            }
        }

        func shutdown() async throws -> Bool {
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
