//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import SwiftAsyncStream

extension Internals {

    package struct UnsafeTask<Element: Sendable>: Sendable, Hashable {

        /// Orders the ending against the request itself.
        ///
        /// `TaskSeed` already guarantees that cancelling and releasing cannot both fire, so
        /// what is left to arbitrate is those against `whenComplete`, which runs on the event
        /// loop. Both sides claim through here, on that loop, so exactly one wins.
        private final class State: @unchecked Sendable {

            private let lock = Lock()
            private var _isRunning = true

            /// - Returns: `true` for the first caller, `false` for everyone after.
            package func finish() -> Bool {
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

        package init(
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

        package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.seed === rhs.seed
        }

        // MARK: - Internal methods

        package func response() async throws -> Element {
            try await withTaskCancellationHandler(
                operation: task.futureResult.get,
                onCancel: seed.callAsFunction
            )
        }

        package func callAsFunction() -> TaskSeed {
            seed
        }

        package func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(seed))
        }
    }
}
