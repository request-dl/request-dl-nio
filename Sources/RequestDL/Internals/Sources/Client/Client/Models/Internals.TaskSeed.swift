//
// See LICENSE for this package's licensing information.
//


extension Internals {

    /// The handle that cancels an in flight request.
    ///
    /// Cancelling and releasing are separate on purpose, even though both end the request.
    ///
    /// Dropping the response still cancels: leaving it running would mean a `break` out of a
    /// body stream keeps downloading for nobody, and an endless stream keeps its connection
    /// open forever.
    ///
    /// What changed is where it happens. `deinit` used to call cancel directly, on whatever
    /// thread held the last reference, unordered against the request finishing. ``release``
    /// puts it on the request's own event loop instead, alongside the completion handler, so
    /// the two cannot both claim the ending.
    final class TaskSeed: Sendable, Hashable {

        static var withoutCancellation: TaskSeed {
            TaskSeed(cancel: {}, release: {})
        }

        private let cancel: @Sendable () -> Void
        private let release: @Sendable () -> Void

        init(
            cancel: @escaping @Sendable () -> Void,
            release: @escaping @Sendable () -> Void
        ) {
            self.cancel = cancel
            self.release = release
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
            release()
        }
    }
}
