/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOFoundationCompat

struct AsyncBytes: AsyncSequence {

    typealias Element = Data

    typealias AsyncStream = AsyncThrowingStream<Element, Error>

    fileprivate let seed: ObjectIdentifier
    fileprivate let asyncStream: AsyncThrowingStream<DataBuffer, Error>

    init(_ dataStream: DataStream<DataBuffer>) {
        self.seed = ObjectIdentifier(dataStream)
        self.asyncStream = dataStream.asyncStream()
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(asyncStream.makeAsyncIterator())
    }
}

extension AsyncBytes {

    struct Iterator: AsyncIteratorProtocol {

        var iterator: AsyncThrowingStream<DataBuffer, Error>.AsyncIterator

        init(_ iterator: AsyncThrowingStream<DataBuffer, Error>.AsyncIterator) {
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

extension AsyncBytes: Equatable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.seed == rhs.seed
    }
}

extension AsyncBytes {

    fileprivate func data() async throws -> Data {
        var items = [Data]()

        for try await data in self {
            items.append(data)
        }

        return items.reduce(Data(), +)
    }
}

extension Data {

    init(_ asyncBytes: AsyncBytes) async throws {
        self = try await asyncBytes.data()
    }
}
