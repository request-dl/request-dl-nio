import NIOCore

//
// See LICENSE for this package's licensing information.
//
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals {

    package struct AsyncBytes: Sendable, Hashable, AsyncSequence {

        package struct Iterator: AsyncIteratorProtocol {

            // MARK: - Internal properties

            package var iterator: Internals.AsyncStream<Internals.DataBuffer>.AsyncIterator

            // MARK: - Inits

            package init(_ iterator: Internals.AsyncStream<Internals.DataBuffer>.AsyncIterator) {
                self.iterator = iterator
            }

            // MARK: - Internal methods

            package mutating func next() async throws -> Data? {
                guard var dataBuffer = try await iterator.next() else {
                    return nil
                }

                return await dataBuffer.readData(dataBuffer.readableBytes)
            }
        }

        package typealias Element = Data

        // MARK: - Internal properties

        package let logger: Internals.TaskLogger?
        package let totalSize: Int

        // MARK: - Private properties

        fileprivate let asyncBuffers: Internals.AsyncStream<Internals.DataBuffer>

        // MARK: - Inits

        package init(
            logger: Internals.TaskLogger?,
            totalSize: Int,
            stream asyncBuffers: Internals.AsyncStream<DataBuffer>
        ) {
            self.logger = logger
            self.totalSize = totalSize
            self.asyncBuffers = asyncBuffers
        }

        // MARK: - Internal methods

        package func makeAsyncIterator() -> Iterator {
            Iterator(asyncBuffers.makeAsyncIterator())
        }
    }
}
