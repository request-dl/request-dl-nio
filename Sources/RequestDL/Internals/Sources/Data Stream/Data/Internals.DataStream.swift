/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    class DataStream<Value> {

        private var queue: AnyStream<Value>
        private let operationQueue: OperationQueue
        private var isQueueing = false

        init() {
            self.queue = .init(QueueStream())
            self.operationQueue = OperationQueue()

            operationQueue.qualityOfService = .background
            operationQueue.maxConcurrentOperationCount = 1
        }

        func append(_ value: Result<Value, Error>) {
            operationQueue.addOperation {
                switch value {
                case .success(let value):
                    self.queue.append(.success(value))
                case .failure(let error):
                    self.queue.append(.failure(error))
                }
            }
        }

        func close() {
            operationQueue.addOperation {
                self.queue.append(.success(nil))
            }
        }

        func observe(_ closure: @escaping (Result<Value?, Error>) -> Void) {
            isQueueing = true
            operationQueue.addOperation {
                let queue = self.queue
                let dispatchStream = DispatchStream(closure)

                do {
                    while let value = try queue.next() {
                        dispatchStream.append(.success(value))
                    }
                } catch {
                    dispatchStream.append(.failure(error))
                }

                if !queue.isOpen && dispatchStream.isOpen {
                    dispatchStream.append(.success(nil))
                }

                self.queue = .init(dispatchStream)
                self.isQueueing = false
            }
        }
    }
}

extension Internals.DataStream {

    func asyncStream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { [self] continuation in
            self.observe {
                switch $0 {
                case .failure(let error):
                    continuation.finish(throwing: error)
                case .success(let value):
                    if let value = value {
                        continuation.yield(value)
                    } else {
                        continuation.finish(throwing: nil)
                    }
                }
            }
        }
    }
}
