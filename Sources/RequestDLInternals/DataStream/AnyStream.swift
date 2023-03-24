/*
 See LICENSE for this package's licensing information.
*/

import Foundation

class AnyStream<Value>: StreamProtocol {

    private let openClosure: () -> Bool
    private let appendClosure: (Result<Value?, Error>) -> Void
    private var nextClosure: () throws -> Value?

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

    var isOpen: Bool {
        openClosure()
    }

    func append(_ value: Result<Value?, Error>) {
        appendClosure(value)
    }

    func next() throws -> Value? {
        try nextClosure()
    }
}
