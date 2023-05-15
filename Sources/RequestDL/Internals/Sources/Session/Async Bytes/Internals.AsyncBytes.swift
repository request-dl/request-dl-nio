/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct AsyncBytes: Sendable, Hashable, AsyncSequence {

        struct Iterator: AsyncIteratorProtocol {

            // MARK: - Internal properties

            var iterator: Internals.AsyncStream<Internals.DataBuffer>.AsyncIterator

            // MARK: - Inits

            init(_ iterator: Internals.AsyncStream<Internals.DataBuffer>.AsyncIterator) {
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

        typealias Element = Data

        // MARK: - Private properties

        fileprivate let asyncBuffers: Internals.AsyncStream<Internals.DataBuffer>

        // MARK: - Inits

        init(_ asyncBuffers: Internals.AsyncStream<DataBuffer>) {
            self.asyncBuffers = asyncBuffers
        }

        // MARK: - Internal methods

        func makeAsyncIterator() -> Iterator {
            Iterator(asyncBuffers.makeAsyncIterator())
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

// MARK: - Data extension

extension Data {

    init(_ asyncBytes: Internals.AsyncBytes) async throws {
        self = try await asyncBytes.data()
    }
}
