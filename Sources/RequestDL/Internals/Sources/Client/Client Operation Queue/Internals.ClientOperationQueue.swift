//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// Counts the requests a client currently has in flight.
    ///
    /// This used to be a doubly linked list with a permanent root and a lock on every node.
    /// Completing an operation touched its neighbours, so it held its own lock while taking
    /// theirs, and two adjacent requests finishing at the same time deadlocked each other:
    /// the first held A and wanted B, the second held B and wanted A. `Lock` is not reentrant,
    /// so it was permanent, and it happened inside a cooperative pool thread while holding the
    /// client's `AsyncLock`.
    ///
    /// The list existed only to answer "is anything running", which a counter answers without
    /// any of that.
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
