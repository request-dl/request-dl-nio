/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    @HTTPClientActor
    class ClientOperation {

        private(set) weak var previous: ClientOperation?
        private(set) var next: ClientOperation?
        private weak var delegate: QueueClientOperationDelegate?

        init(delegate: QueueClientOperationDelegate?) {
            self.delegate = delegate
        }

        func connect(to operation: ClientOperation) {
            operation.next = self
            self.previous = operation
        }

        func complete() {
            previous?.next = next
            next?.previous = previous

            delegate?.operationDidComplete(self)
        }
    }
}
