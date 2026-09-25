//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Thrown by ``Internals/AsyncBytes/Iterator`` when a chunk it already received from the network
/// fails to read back out of its own backing storage.
///
/// `Internals.Buffer.readData(_:)` returns `nil` for this same underlying condition (the backing
/// resource -- e.g. a temp file backing a disk-spilled chunk -- became unreadable, was deleted, or
/// otherwise failed), which is indistinguishable, at that layer, from "nothing to read here." At
/// the `AsyncSequence` layer, though, that ambiguity must not survive: mapping it to a plain `nil`
/// would end the sequence exactly like reaching the end of a *successful* response, silently
/// truncating the body instead of surfacing the failure.
package struct AsyncBytesReadError: Swift.Error, CustomStringConvertible, Sendable {

    package var description: String {
        "A previously received chunk could not be read back from its backing storage."
    }

    package init() {}
}

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

                let readableBytes = dataBuffer.readableBytes

                // A genuinely empty chunk (`readableBytes == .zero`) is not itself a failure --
                // some producers forward one deliberately -- and some storage backends report
                // "resource unavailable" for a zero-length read regardless of whether anything is
                // actually wrong, so this returns the trivial answer directly rather than routing
                // it through `readData` at all.
                guard readableBytes > .zero else {
                    return Data()
                }

                // `readData` is asked for exactly `readableBytes`, always a valid range by
                // construction, so a `nil` here cannot mean "the range wasn't readable" the way
                // it can for an arbitrary caller-chosen length -- it means the chunk's backing
                // storage itself failed. That must not be reported as a quiet end of stream (see
                // `AsyncBytesReadError`'s own doc comment).
                guard let data = await dataBuffer.readData(readableBytes) else {
                    throw AsyncBytesReadError()
                }

                return data
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
