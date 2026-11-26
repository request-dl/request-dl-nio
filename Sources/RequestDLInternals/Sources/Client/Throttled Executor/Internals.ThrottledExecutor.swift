//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// Gates how many operations may be admitted at once, independent of which concrete client
    /// (`Internals.Client`, and eventually a URLSession-backed one) is doing the admitting.
    ///
    /// Hoisted out of `Internals.Client` so `maximumConcurrentConnections` behaves identically
    /// regardless of executor, rather than each concrete client owning its own copy of the same
    /// semaphore logic and risking the two drifting apart.
    ///
    /// - Important: A throttle is a handle on a semaphore, and what makes the limit one of the
    /// session is that every client of the session holds a handle on the *same* semaphore.
    /// `Internals.ClientManager.throttledExecutor(provider:maximumConcurrentConnections:)` is what
    /// hands them out: one semaphore per session provider and limit, for as long as some client,
    /// waiter or slot holder is using it. A client that is given none (a test, mostly) makes a
    /// semaphore of its own, and the limit is then its own.
    package struct ThrottledExecutor: Sendable {

        // MARK: - Private properties

        /// `nil` when no limit was configured, leaving operations unthrottled.
        private let semaphore: AsyncCancellableSemaphore?

        // MARK: - Inits

        /// Takes part in a limit that other throttles already share, instead of making a limit of
        /// its own. See `Internals.ClientManager.throttledExecutor(provider:maximumConcurrentConnections:)`.
        package init(sharing semaphore: AsyncCancellableSemaphore) {
            self.semaphore = semaphore
        }

        /// A non-positive limit is treated as no limit at all. It reaches here unvalidated (from
        /// `Session.maximumConcurrentConnections(_:)`, or a `Configured` config file), and
        /// neither alternative is survivable: `AsyncCancellableSemaphore.init(permits:)` traps on a
        /// negative count, even in release builds, and a zero-permit semaphore is a gate that no
        /// request ever opens (nothing here holds a slot to give back), so every request through
        /// the session would wait forever.
        package init(maximumConcurrentConnections: Int?) {
            semaphore =
                maximumConcurrentConnections
                .flatMap { $0 > .zero ? $0 : nil }
                .map { AsyncCancellableSemaphore(permits: $0) }
        }

        // MARK: - Internal methods

        /// Waits for a free slot, then hands back a closure that releases it.
        ///
        /// Waiting is cancellable (`AsyncCancellableSemaphore`, unlike `AsyncSemaphore`, which is
        /// cancellation transparent): a caller whose `Task` is cancelled before it was handed a slot
        /// stops waiting at once and throws, without having taken one, and without anyone behind it
        /// losing their place. With no limit configured there is nothing to wait for, and the call
        /// returns without looking at cancellation; the caller decides what to do with a cancelled
        /// request, as it always did.
        ///
        /// There is no `withPermit`-style scoped variant here because the operations this guards
        /// (an in-flight `HTTPClient.Task`, a future URLSession task) outlive the call that
        /// starts them. The caller owns calling the returned closure exactly once, whenever it
        /// considers the throttled operation complete.
        ///
        /// - Parameter idle: The read timeout of the execution that waits, which does not count the
        /// wait: until a slot is free the request is not on the network, and it is the session's own
        /// limit that holds it back, not the server's silence. The execution this task is part of
        /// (`Internals.IdleDeadline.queueing`) unless told otherwise, for a caller on a task of its
        /// own.
        /// - Throws: `CancellationError` if the current task is cancelled while waiting for a slot.
        package func acquire(
            pausing idle: Internals.IdleDeadline? = Internals.IdleDeadline.queueing
        ) async throws -> @Sendable () -> Void {
            if let semaphore {
                idle?.pause()
                defer { idle?.resume() }

                try await semaphore.wait()
            }

            let semaphore = self.semaphore
            return { semaphore?.signal() }
        }
    }
}

// MARK: - Testing

@_spi(Testing)
extension Internals.ThrottledExecutor {

    /// The semaphore backing this throttle, `nil` when no limit was configured.
    ///
    /// Same escape-hatch shape as `Internals.Client.connectionSemaphoreForTesting`, which this
    /// backs: gated behind `@_spi(Testing)` on top of `package` so a test can wait for an exact
    /// ``AsyncCancellableSemaphore/waitingCount`` instead of sleeping a fixed duration and hoping the
    /// right number of requests reached the semaphore by then.
    package var semaphoreForTesting: AsyncCancellableSemaphore? {
        semaphore
    }
}
