/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

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

        // MARK: - Internal methods

        func execute<Delegate: HTTPClientResponseDelegate>(
            request: HTTPClient.Request,
            delegate: Delegate
        ) -> EventLoopFuture<Delegate.Response> {
            let operation = manager.operation()

            return _client.execute(
                request: request,
                delegate: delegate
            ).futureResult.always { _ in
                _Concurrency.Task {
                    await self.lock.withLockVoid {
                        operation.complete()
                    }
                }
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
