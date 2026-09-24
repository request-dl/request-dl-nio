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
    package struct ThrottledExecutor: Sendable {

        // MARK: - Private properties

        /// `nil` when no limit was configured, leaving operations unthrottled.
        private let semaphore: AsyncSemaphore?

        // MARK: - Inits

        /// A non-positive limit is treated as no limit at all. It reaches here unvalidated (from
        /// `Session.maximumConcurrentConnections(_:)`, or a `Configured` config file), and
        /// neither alternative is survivable: `AsyncSemaphore.init(permits:)` traps on a negative
        /// count, even in release builds, and a zero-permit semaphore can never be acquired, so
        /// every request through the session would wait forever.
        package init(maximumConcurrentConnections: Int?) {
            semaphore =
                maximumConcurrentConnections
                .flatMap { $0 > .zero ? $0 : nil }
                .map { AsyncSemaphore(permits: $0) }
        }

        // MARK: - Internal methods

        /// Waits for a free slot, then hands back a closure that releases it.
        ///
        /// There is no `withPermit`-style scoped variant here because the operations this guards
        /// (an in-flight `HTTPClient.Task`, a future URLSession task) outlive the call that
        /// starts them. The caller owns calling the returned closure exactly once, whenever it
        /// considers the throttled operation complete.
        package func acquire() async -> @Sendable () -> Void {
            await semaphore?.wait()

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
    /// ``AsyncSemaphore/waitingCount`` instead of sleeping a fixed duration and hoping the right
    /// number of requests reached the semaphore by then.
    public var semaphoreForTesting: AsyncSemaphore? {
        semaphore
    }
}
