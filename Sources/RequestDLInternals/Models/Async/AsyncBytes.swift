/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOFoundationCompat

public struct AsyncBytes: AsyncSequence {
    public typealias Element = Data

    public typealias AsyncStream = AsyncThrowingStream<Element, Error>

    fileprivate let seed: ObjectIdentifier
    fileprivate let asyncStream: AsyncThrowingStream<DataBuffer, Error>

    init(_ dataStream: DataStream<DataBuffer>) {
        self.seed = ObjectIdentifier(dataStream)
        self.asyncStream = dataStream.asyncStream()
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(asyncStream.makeAsyncIterator())
    }
}

extension AsyncBytes {

    public struct Iterator: AsyncIteratorProtocol {

        var iterator: AsyncThrowingStream<DataBuffer, Error>.AsyncIterator

        init(_ iterator: AsyncThrowingStream<DataBuffer, Error>.AsyncIterator) {
            self.iterator = iterator
        }

        public mutating func next() async throws -> Data? {
            guard var dataBuffer = try await iterator.next() else {
                return nil
            }

            return dataBuffer.readData(dataBuffer.readableBytes)
        }
    }
}

extension AsyncBytes: Equatable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
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

    public init(_ asyncBytes: AsyncBytes) async throws {
        self = try await asyncBytes.data()
    }
}
