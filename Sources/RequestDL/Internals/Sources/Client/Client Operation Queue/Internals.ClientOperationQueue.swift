/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    final class ClientOperationQueue: @unchecked Sendable {

        private final class Root: Internals.ClientOperation {

            override func complete() {
                /**
                 * This function intentionally has no implementation and is meant to be used as a permanent
                 * root for a `ClientOperationQueue`. By not implementing the function, we can ensure
                 * that the root operation is always present in memory and is held by the queue.
                 *
                 * The default implementation updates the next and previous references that point to this
                 * operation, but since the root is intended to exist indefinitely, we do not want to modify these
                 * references.
                 */
            }
        }

        // MARK: - Internal properties

        var isRunning: Bool {
            lock.withLock {
                _last == nil || _last !== root
            }
        }

        // MARK: - Private properties

        private let lock = Lock()

        private let root: Root

        // MARK: - Unsafe properties

        private weak var _last: ClientOperation?

        // MARK: - Inits

        init() {
            let root = Root(delegate: nil)

            self.root = root
            self._last = root
        }

        // MARK: - Internals methods

        func operation() -> ClientOperation {
            lock.withLock {
                let last = _last ?? root
                let operation = ClientOperation(delegate: self)
                operation.connect(to: last)
                self._last = operation
                return operation
            }
        }
    }
}

// MARK: - QueueClientOperationDelegate

extension Internals.ClientOperationQueue: QueueClientOperationDelegate {

    func operationDidComplete(_ operation: Internals.ClientOperation) {
        lock.withLock {
            if operation === _last {
                _last = _last?.previous ?? root
            }
        }
    }
}
