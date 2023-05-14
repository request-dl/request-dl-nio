/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    @available(*, deprecated)
    final class DataStream<Value: Sendable>: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _stream: AnyStream<Value>

        // MARK: - Inits

        init() {
            _stream = .init(QueueStream())
        }

        // MARK: - Internal methods

        func append(_ value: Result<Value, Error>) {
            lock.withLockVoid {
                switch value {
                case .success(let value):
                    _stream.append(.success(value))
                case .failure(let error):
                    _stream.append(.failure(error))
                }
            }
        }

        func close() {
            lock.withLockVoid {
                _stream.append(.success(nil))
            }
        }

        func asyncStream() -> AsyncThrowingStream<Value, Error> {
            AsyncThrowingStream { [self] continuation in
                observe {
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

        /// This method is available internally for tests only
        func observe(_ closure: @escaping @Sendable (Result<Value?, Error>) -> Void) {
            lock.withLockVoid {
                let _stream = _stream
                let dispatchStream = DispatchStream(closure)

                do {
                    while let value = try _stream.next() {
                        dispatchStream.append(.success(value))
                    }
                } catch {
                    dispatchStream.append(.failure(error))
                }

                if !_stream.isOpen && dispatchStream.isOpen {
                    dispatchStream.append(.success(nil))
                }

                self._stream = .init(dispatchStream)
            }
        }
    }
}
