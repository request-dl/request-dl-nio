/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    @available(*, deprecated)
    final class AnyStream<Value: Sendable>: StreamProtocol {

        // MARK: - Internal properties

        var isOpen: Bool {
            openClosure()
        }

        // MARK: - Private properties

        private let openClosure: @Sendable () -> Bool
        private let appendClosure: @Sendable (Result<Value?, Error>) -> Void
        private let nextClosure: @Sendable () throws -> Value?

        // MARK: - Inits

        init<Stream: StreamProtocol>(_ stream: Stream) where Stream.Value == Value {
            openClosure = {
                stream.isOpen
            }

            appendClosure = {
                stream.append($0)
            }

            nextClosure = {
                try stream.next()
            }
        }

        // MARK: - Internal methods

        func append(_ value: Result<Value?, Error>) {
            appendClosure(value)
        }

        func next() throws -> Value? {
            try nextClosure()
        }
    }
}
