/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

extension Internals {

    struct UnsafeTask<Element: Sendable>: Sendable, Hashable {

        fileprivate final class RunningState: @unchecked Sendable {
            var isRunning = true
        }

        // MARK: - Private properties

        private let task: HTTPClient.Task<Element>
        private let seed: TaskSeed

        // MARK: - Inits

        init(
            _ task: HTTPClient.Task<Element>,
            completion: @Sendable @escaping () -> Void
        ) {
            let lock = Lock()
            let runningState = RunningState()

            seed = TaskSeed {
                lock.withLock {
                    guard runningState.isRunning else {
                        return
                    }

                    runningState.isRunning = false
                    task.cancel()
                    completion()
                }
            }

            task.futureResult.whenComplete { _ in
                lock.withLock {
                    guard runningState.isRunning else {
                        return
                    }

                    runningState.isRunning = false
                    completion()
                }
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
