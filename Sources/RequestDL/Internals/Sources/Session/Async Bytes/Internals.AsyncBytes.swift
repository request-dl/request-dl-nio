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

        // MARK: - Internal properties

        let logger: Internals.TaskLogger?
        let totalSize: Int

        // MARK: - Private properties

        fileprivate let asyncBuffers: Internals.AsyncStream<Internals.DataBuffer>

        // MARK: - Inits

        init(
            logger: Internals.TaskLogger?,
            totalSize: Int,
            stream asyncBuffers: Internals.AsyncStream<DataBuffer>
        ) {
            self.logger = logger
            self.totalSize = totalSize
            self.asyncBuffers = asyncBuffers
        }

        // MARK: - Internal methods

        func makeAsyncIterator() -> Iterator {
            Iterator(asyncBuffers.makeAsyncIterator())
        }
    }
}
