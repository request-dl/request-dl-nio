//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// Counts the requests a client currently has in flight.
    ///
    /// - Important: Must stay a plain counter, not a doubly linked list with a lock per node.
    /// Completing an operation touches its neighbours, so a node holds its own lock while
    /// taking theirs — two adjacent requests finishing at the same time deadlock each other:
    /// the first holds A and wants B, the second holds B and wants A. `Lock` is not reentrant,
    /// so that deadlock is permanent, and it would happen inside a cooperative pool thread
    /// while holding the client's `AsyncLock`.
    ///
    /// The only question this needs to answer is "is anything running", which a counter answers
    /// without any of that.
    package final class ClientOperationQueue: @unchecked Sendable {

        // MARK: - Internal properties

        package var isRunning: Bool {
            lock.withLock { _count > .zero }
        }

        /// Bumped every time an operation finishes. Purely a counter, with no notion of a clock
        /// of its own on purpose: `Internals.ClientManager`'s idle-cleanup sweep and ceiling
        /// eviction are what need to tell "genuinely idle" apart from "nothing in flight *right
        /// now*, but an operation completed a moment ago" -- e.g. between two sequential calls
        /// on the same resolved client, such as `Internals.CacheControl`'s conditional-
        /// revalidation `HEAD` followed by the real `GET`. `isRunning` alone reads `false` for the
        /// whole gap between the two, which is exactly the window a sweep or an at-capacity
        /// insert could otherwise retire this client in, out from under a caller who fully
        /// intends to use it again. Comparing this against the value `Internals.ClientManager`
        /// last recorded lets it recognize "active since I last looked" without this type having
        /// to know what a monotonic clock even is.
        package var generation: UInt64 {
            lock.withLock { _generation }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _count = 0
        private var _generation: UInt64 = .zero

        // MARK: - Inits

        package init() {}

        // MARK: - Internals methods

        package func operation() -> ClientOperation {
            lock.withLock { _count += 1 }
            return ClientOperation(delegate: self)
        }
    }
}

// MARK: - QueueClientOperationDelegate

extension Internals.ClientOperationQueue: QueueClientOperationDelegate {

    package func operationDidComplete(_ operation: Internals.ClientOperation) {
        lock.withLock {
            _count -= 1
            _generation += 1
        }
    }
}
