/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    final class DispatchStream<Value: Sendable>: StreamProtocol, @unchecked Sendable {

        // MARK: - Internal properties

        var isOpen: Bool {
            lock.withLock {
                _closure != nil
            }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _closure: (@Sendable (Result<Value?, Error>) -> Void)?

        // MARK: - Inits

        init(_ closure: @escaping @Sendable (Result<Value?, Error>) -> Void) {
            self._closure = closure
        }

        // MARK: - Internal methods

        func append(_ value: Result<Value?, Error>) {
            lock.withLockVoid {
                guard let closure = _closure else {
                    return
                }

                switch value {
                case .failure(let failure):
                    closure(.failure(failure))
                    self._closure = nil
                case .success(let value):
                    closure(.success(value))

                    if value == nil {
                        self._closure = nil
                    }
                }
            }
        }

        func next() throws -> Value? {
            nil
        }
    }
}
