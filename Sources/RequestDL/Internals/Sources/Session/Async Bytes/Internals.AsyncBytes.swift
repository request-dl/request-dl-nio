/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct AsyncBytes: Sendable, AsyncSequence {

        typealias Element = Data

        typealias AsyncStream = AsyncThrowingStream<Element, Error>

        // MARK: - Private properties

        fileprivate let seed: ObjectIdentifier
        fileprivate let asyncStream: AsyncThrowingStream<Internals.DataBuffer, Error>

        // MARK: - Inits

        init(_ dataStream: Internals.DataStream<DataBuffer>) {
            self.seed = ObjectIdentifier(dataStream)
            self.asyncStream = dataStream.asyncStream()
        }

        // MARK: - Internal methods

        func makeAsyncIterator() -> Iterator {
            Iterator(asyncStream.makeAsyncIterator())
        }

        // MARK: - Private methods

        fileprivate func data() async throws -> Data {
            var items = [Data]()

            for try await data in self {
                items.append(data)
            }

            return items.reduce(Data(), +)
        }
    }
}

// MARK: - Hashable

extension Internals.AsyncBytes: Hashable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.seed == rhs.seed
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(seed)
    }
}

extension Internals.AsyncBytes {

    struct Iterator: AsyncIteratorProtocol {

        // MARK: - Internal properties

        var iterator: AsyncThrowingStream<Internals.DataBuffer, Error>.AsyncIterator

        // MARK: - Inits

        init(_ iterator: AsyncThrowingStream<Internals.DataBuffer, Error>.AsyncIterator) {
            self.iterator = iterator
        }

        // MARK: - Internal methods

        mutating func next() async throws -> Data? {
            guard var dataBuffer = try await iterator.next() else {
                return nil
            }

            return dataBuffer.readData(dataBuffer.readableBytes)
        }
    }
}

// MARK: - Data extension

extension Data {

    init(_ asyncBytes: Internals.AsyncBytes) async throws {
        self = try await asyncBytes.data()
    }
}
