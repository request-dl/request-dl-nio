/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    class ClientOperation: @unchecked Sendable {

        // MARK: - Internal properties

        private(set) weak var previous: ClientOperation? {
            get { lock.withLock { _previous } }
            set { lock.withLock { _previous = newValue } }
        }

        private(set) var next: ClientOperation? {
            get { lock.withLock { _next } }
            set { lock.withLock { _next = newValue } }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private weak var _previous: ClientOperation?
        private var _next: ClientOperation?
        private weak var _delegate: QueueClientOperationDelegate?

        // MARK: - Init

        init(delegate: QueueClientOperationDelegate?) {
            self._delegate = delegate
        }

        // MARK: - Internal methods

        func connect(to operation: ClientOperation) {
            lock.withLockVoid {
                operation.next = self
                self._previous = operation
            }
        }

        func complete() {
            lock.withLockVoid {
                _previous?.next = _next
                _next?.previous = _previous
            }

            _delegate?.operationDidComplete(self)
        }
    }
}
