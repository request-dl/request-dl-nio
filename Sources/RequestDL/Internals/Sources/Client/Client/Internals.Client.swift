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

        func execute(request: HTTPClient.Request) -> UnsafeTask<ResponseAccumulator.Response> {
            execute(
                request: request,
                delegate: ResponseAccumulator(request: request)
            )
        }

        func execute<Delegate: HTTPClientResponseDelegate>(
            request: HTTPClient.Request,
            delegate: Delegate
        ) -> UnsafeTask<Delegate.Response> {
            let operation = manager.operation()

            let task = _client.execute(
                request: request,
                delegate: delegate
            )

            return UnsafeTask(task) { _ in
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

extension Internals {

    enum TaskStatus {
        case finished
        case cancelled
    }

    final class TaskSeed: Sendable, Hashable {

        static var withoutCancellation: TaskSeed {
            TaskSeed {}
        }

        private let cancel: @Sendable () -> Void

        init(_ cancel: @escaping @Sendable () -> Void) {
            self.cancel = cancel
        }

        static func == (lhs: Internals.TaskSeed, rhs: Internals.TaskSeed) -> Bool {
            lhs === rhs
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }

        @Sendable
        func callAsFunction() {
            cancel()
        }

        deinit {
            cancel()
        }
    }

    struct UnsafeTask<Element>: Sendable, Hashable {

        fileprivate final class RunningState: @unchecked Sendable {

            var isRunning: Bool {
                get { lock.withLock { _isRunning } }
                set { lock.withLock { _isRunning = newValue } }
            }

            private let lock = Lock()

            private var _isRunning = true
        }

        // MARK: - Private properties

        private let task: HTTPClient.Task<Element>
        private let seed: TaskSeed

        // MARK: - Inits

        init(
            _ task: HTTPClient.Task<Element>,
            completion: @escaping (TaskStatus) -> Void
        ) {
            let runningState = RunningState()

            seed = TaskSeed {
                guard runningState.isRunning else {
                    return
                }

                runningState.isRunning = false
                task.cancel()
                completion(.cancelled)
            }

            task.futureResult.whenComplete { _ in
                guard runningState.isRunning else {
                    return
                }

                runningState.isRunning = false
                completion(.finished)
            }

            self.task = task
        }

        // MARK: - Internal static methods

        static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.seed === rhs.seed
        }

        // MARK: - Internal methods

        func response() async throws -> Element {
            try await withTaskCancellationHandler(
                operation: task.futureResult.get,
                onCancel: seed.callAsFunction
            )
        }

        func callAsFunction() -> TaskSeed {
            seed
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(seed))
        }
    }
}
