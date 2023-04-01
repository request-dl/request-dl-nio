/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOFoundationCompat

extension Internals {

    struct AsyncBytes: AsyncSequence {

        typealias Element = Data

        typealias AsyncStream = AsyncThrowingStream<Element, Error>

        fileprivate let seed: ObjectIdentifier
        fileprivate let asyncStream: AsyncThrowingStream<Internals.DataBuffer, Error>

        init(_ dataStream: Internals.DataStream<DataBuffer>) {
            self.seed = ObjectIdentifier(dataStream)
            self.asyncStream = dataStream.asyncStream()
        }

        func makeAsyncIterator() -> Iterator {
            Iterator(asyncStream.makeAsyncIterator())
        }
    }
}

extension Internals.AsyncBytes {

    struct Iterator: AsyncIteratorProtocol {

        var iterator: AsyncThrowingStream<Internals.DataBuffer, Error>.AsyncIterator

        init(_ iterator: AsyncThrowingStream<Internals.DataBuffer, Error>.AsyncIterator) {
            self.iterator = iterator
        }

        mutating func next() async throws -> Data? {
            guard var dataBuffer = try await iterator.next() else {
                return nil
            }

            return dataBuffer.readData(dataBuffer.readableBytes)
        }
    }
}

extension Internals.AsyncBytes: Equatable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.seed == rhs.seed
    }
}

extension Internals.AsyncBytes {

    fileprivate func data() async throws -> Data {
        var items = [Data]()

        for try await data in self {
            items.append(data)
        }

        return items.reduce(Data(), +)
    }
}

extension Data {

    init(_ asyncBytes: Internals.AsyncBytes) async throws {
        self = try await asyncBytes.data()
    }
}
