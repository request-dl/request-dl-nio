/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

extension Internals {

    @HTTPClientActor
    class Client {

        private let manager = Internals.ClientOperationQueue()
        private let _client: HTTPClient
        private var isClosed: Bool

        init(
            eventLoopGroupProvider: HTTPClient.EventLoopGroupProvider,
            configuration: HTTPClient.Configuration
        ) {
            isClosed = false
            _client = .init(
                eventLoopGroupProvider: eventLoopGroupProvider,
                configuration: configuration
            )
        }

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
                    await operation.complete()
                }
            }
        }

        func shutdown() async throws -> Bool {
            guard !isRunning && !isClosed else {
                return false
            }

            try await _client.shutdown()
            isClosed = true
            return true
        }

        var isRunning: Bool {
            manager.isRunning
        }
    }
}
