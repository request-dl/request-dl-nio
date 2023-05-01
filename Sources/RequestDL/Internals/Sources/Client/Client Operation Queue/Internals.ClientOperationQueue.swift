/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    @HTTPClientActor
    class ClientOperationQueue {

        private let root: Root
        private weak var last: ClientOperation?

        init() {
            let root = Root(delegate: nil)

            self.root = root
            self.last = root
        }

        func operation() -> ClientOperation {
            let last = last ?? root
            let operation = ClientOperation(delegate: self)
            operation.connect(to: last)
            self.last = operation
            return operation
        }

        var isRunning: Bool {
            last == nil || last !== root
        }
    }
}

extension Internals.ClientOperationQueue: QueueClientOperationDelegate {

    func operationDidComplete(_ operation: Internals.ClientOperation) {
        if operation === last {
            last = last?.previous ?? root
        }
    }
}

extension Internals.ClientOperationQueue {

    fileprivate final class Root: Internals.ClientOperation {

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
}
