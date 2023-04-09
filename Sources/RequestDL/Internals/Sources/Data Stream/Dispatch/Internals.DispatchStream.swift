/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    class DispatchStream<Value>: StreamProtocol {

        private var closure: ((Result<Value?, Error>) -> Void)?

        var isOpen: Bool {
            closure != nil
        }

        init(_ closure: @escaping (Result<Value?, Error>) -> Void) {
            self.closure = closure
        }

        func append(_ value: Result<Value?, Error>) {
            guard let closure = closure else {
                return
            }

            switch value {
            case .failure(let failure):
                closure(.failure(failure))
                self.closure = nil
            case .success(let value):
                closure(.success(value))

                if value == nil {
                    self.closure = nil
                }
            }
        }

        func next() throws -> Value? {
            nil
        }
    }
}
