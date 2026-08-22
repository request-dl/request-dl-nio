//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// The handle that ends an in flight request.
    ///
    /// Ending happens at most once, whichever way it is reached. Cancelling explicitly and
    /// letting the response go out of scope are both endings, and before this the two could
    /// both fire, which on the cached path ran the teardown twice and only got away with it
    /// because those operations happen to be idempotent.
    ///
    /// Dropping the response still cancels: leaving it running would mean a `break` out of a
    /// body stream keeps downloading for nobody, and an endless stream keeps its connection
    /// open forever.
    ///
    /// ``release`` exists separately from ``cancel`` only for sources that have a wire to
    /// order against. ``UnsafeTask`` uses it to move the teardown onto the request's own event
    /// loop, alongside the completion handler, so the two cannot both claim the ending.
    /// Anything without that distinction uses ``init(_:)``.
    package final class TaskSeed: @unchecked Sendable, Hashable {

        // MARK: - Internal static properties

        package static var withoutCancellation: TaskSeed {
            TaskSeed {}
        }

        // MARK: - Private properties

        private let lock = Lock()

        private let _cancel: @Sendable () -> Void
        private let _release: @Sendable () -> Void

        // MARK: - Unsafe properties

        private var _isFinished = false

        // MARK: - Inits

        /// For sources where cancelling and releasing are the same act.
        package convenience init(_ action: @escaping @Sendable () -> Void) {
            self.init(cancel: action, release: action)
        }

        package init(
            cancel: @escaping @Sendable () -> Void,
            release: @escaping @Sendable () -> Void
        ) {
            self._cancel = cancel
            self._release = release
        }

        deinit {
            guard claim() else {
                return
            }

            _release()
        }

        // MARK: - Internal static methods

        package static func == (lhs: Internals.TaskSeed, rhs: Internals.TaskSeed) -> Bool {
            lhs === rhs
        }

        // MARK: - Internal methods

        package func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }

        @Sendable
        package func callAsFunction() {
            guard claim() else {
                return
            }

            _cancel()
        }

        // MARK: - Private methods

        /// - Returns: `true` for the first caller, `false` for everyone after.
        private func claim() -> Bool {
            lock.withLock {
                guard !_isFinished else {
                    return false
                }

                _isFinished = true
                return true
            }
        }
    }
}
