//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Thrown to the reader of a download when bytes that a source reported holding could not be read
/// back out of it: a cached body whose file was removed or whose encrypted entry no longer
/// verifies, or a reading mode that cannot make progress.
///
/// `Internals.Buffer.readData(_:)` returns `nil` for that condition, which is indistinguishable at
/// that layer from "nothing left to read". For the `AsyncSequence` the ambiguity must not survive:
/// mapping it to a plain `nil` would end the sequence exactly like reaching the end of a
/// *successful* response, silently truncating the body instead of surfacing the failure.
///
/// Raised by `Internals.DownloadBuffer` while it reads such a source, ahead of the stream; the
/// elements of the stream are in memory and cannot fail to read.
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

            package var iterator: Internals.AsyncStream<Internals.Chunk>.AsyncIterator

            // MARK: - Inits

            package init(_ iterator: Internals.AsyncStream<Internals.Chunk>.AsyncIterator) {
                self.iterator = iterator
            }

            // MARK: - Internal methods

            package mutating func next() async throws -> Data? {
                // The chunk is in memory and immutable: there is nothing to read back from, and so
                // nothing that can fail. A chunk that is empty (some producers forward one
                // deliberately) is an empty `Data`, not the end of the sequence.
                try await iterator.next()?.data
            }
        }

        package typealias Element = Data

        // MARK: - Internal properties

        package let logger: Internals.TaskLogger?
        package let totalSize: Int

        // MARK: - Private properties

        fileprivate let asyncBuffers: Internals.AsyncStream<Internals.Chunk>

        // MARK: - Inits

        package init(
            logger: Internals.TaskLogger?,
            totalSize: Int,
            stream asyncBuffers: Internals.AsyncStream<Internals.Chunk>
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

// MARK: - Testing

@_spi(Testing)
extension Internals.AsyncBytes {

    /// The window metering the stream these bytes are read from: the one the network producer
    /// pauses on (`Internals.ClientResponseReceiver`), or, behind manual decompression, the
    /// decoder's own. `nil` for every other source.
    public var flowControlWindowForTesting: Internals.FlowControlWindow? {
        asyncBuffers.flowControlWindow
    }
}
