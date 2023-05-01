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

    fileprivate class Root: Internals.ClientOperation {

        override func complete() {
            // TODO: - Missing completion
        }
    }
}
