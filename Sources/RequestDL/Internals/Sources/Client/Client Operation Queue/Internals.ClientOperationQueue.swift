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
    final class ClientOperationQueue: @unchecked Sendable {

        // MARK: - Internal properties

        var isRunning: Bool {
            lock.withLock { _count > .zero }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _count = 0

        // MARK: - Inits

        init() {}

        // MARK: - Internals methods

        func operation() -> ClientOperation {
            lock.withLock { _count += 1 }
            return ClientOperation(delegate: self)
        }
    }
}

// MARK: - QueueClientOperationDelegate

extension Internals.ClientOperationQueue: QueueClientOperationDelegate {

    func operationDidComplete(_ operation: Internals.ClientOperation) {
        lock.withLock { _count -= 1 }
    }
}
