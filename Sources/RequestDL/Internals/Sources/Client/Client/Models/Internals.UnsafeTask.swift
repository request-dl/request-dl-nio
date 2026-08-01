//
// See LICENSE for this package's licensing information.
//

import NIOCore
import AsyncHTTPClient
import SwiftAsyncStream

extension Internals {

    struct UnsafeTask<Element: Sendable>: Sendable, Hashable {

        /// Guards the three things that end a request, so exactly one of them wins.
        private final class State: @unchecked Sendable {

            private let lock = Lock()
            private var _isRunning = true

            /// - Returns: `true` for the first caller, `false` for everyone after.
            func finish() -> Bool {
                lock.withLock {
                    guard _isRunning else {
                        return false
                    }

                    _isRunning = false
                    return true
                }
            }
        }

        // MARK: - Private properties

        private let task: HTTPClient.Task<Element>
        private let seed: TaskSeed

        // MARK: - Inits

        init(
            _ task: HTTPClient.Task<Element>,
            completion: @Sendable @escaping () -> Void
        ) {
            let state = State()

            seed = TaskSeed(
                cancel: {
                    guard state.finish() else {
                        return
                    }

                    task.cancel()
                    completion()
                },
                release: {
                    // Dropping the response still cancels, which is what stops a `break` out of
                    // a body stream from downloading the rest of it for nobody, and what keeps
                    // an endless stream from holding its connection open forever.
                    //
                    // Hopped onto the request's own event loop, though, because that is where
                    // `whenComplete` below runs. Ordering the two there means `finish` decides
                    // between them deterministically: a request that already completed has
                    // claimed the transition, and this becomes a no op instead of cancelling
                    // something that just succeeded.
                    //
                    // A shut down loop drops the closure rather than running it. That releases
                    // `completion`, and with it the operation, whose own `deinit` releases the
                    // slot, so nothing is left counted as busy.
                    task.eventLoop.execute {
                        guard state.finish() else {
                            return
                        }

                        task.cancel()
                        completion()
                    }
                }
            )

            task.futureResult.whenComplete { _ in
                guard state.finish() else {
                    return
                }

                completion()
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
