//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

#if canImport(NIOCore)
import NIOCore
import NIOFoundationEssentialsCompat
#endif

extension Internals {

    /// One piece of a response body, as it travels through `Internals.DownloadBuffer.stream` and
    /// the cache stream beside it.
    ///
    /// An immutable value over `Data`, which is copy on write. Nothing here is a cursor, a store
    /// to lock or a handle to close, so none of what a buffer needs to be shared safely applies:
    ///
    /// - the tee to the cache stream hands both streams the same value. They share the bytes, and
    ///   nobody can write them;
    /// - a reader that stops mid-chunk, or a stream that is dropped, releases the bytes by letting
    ///   go of the value, with nothing to unlock first;
    /// - the order of the elements is the order of the stream, and building one is synchronous,
    ///   which is what the producers' ordering depends on.
    ///
    /// Every element of those streams is already in memory, so a chunk is never file backed and
    /// never encrypted. The file backed buffers are what a cached body is *read from* and what
    /// the cache is *written to*; they sit on either side of the stream and keep their own types.
    ///
    /// ## Invariant
    ///
    /// ``data`` starts at index zero. The reader of a download is handed this `Data` as it is, and
    /// a `Data` that is a slice of a larger one keeps the larger one's indices, so `data[0]`
    /// would trap for whoever expected the start of the chunk. Every initializer upholds it, by
    /// rebasing (copying) anything that does not already start there.
    package struct Chunk: Sendable, Hashable {

        // MARK: - Internal properties

        package let data: Data

        package var readableBytes: Int {
            data.count
        }

        package var isEmpty: Bool {
            data.isEmpty
        }

        // MARK: - Inits

        /// Adopts `data` without copying it, unless it does not start at index zero.
        package init(_ data: Data) {
            if data.startIndex == .zero {
                self.data = data
            } else {
                self.data = data.subdata(in: data.startIndex..<data.endIndex)
            }
        }

        package init(_ bytes: [UInt8]) {
            self.data = Data(bytes)
        }

        /// A chunk of its own, holding a copy of `range` of `block`.
        ///
        /// For a piece cut out of a block that is about to be dropped: the copy is what lets the
        /// block go.
        package init(copying range: Range<Int>, of block: Data) {
            self.data = block.subdata(in: range)
        }

        /// Cuts `range` out of `block`, sharing the block's storage when that does not pin more
        /// of it than is worth keeping.
        ///
        /// A slice keeps the whole allocation it was cut from alive for as long as it lives,
        /// and a chunk can be held for a long time (parked in the stream until a slow reader
        /// arrives, or in the cache's backlog, which is allowed to grow to
        /// ``Internals/DownloadBuffer/cacheBacklogLimit``). A 1 KiB chunk that pinned its whole
        /// 64 KiB block would make that backlog cost up to 64 times what it is metered at.
        ///
        /// So the slice is shared only if it is at least ``sharingThreshold`` of the block, which
        /// bounds the memory held per byte of chunk at twice. Anything smaller is copied out,
        /// which costs the one allocation a chunk of its own needs anyway.
        ///
        /// Sharing is also only possible for a slice that starts at index zero (see the
        /// invariant above), which is the case for the first piece of a block, and for the whole
        /// of it. Every other piece is copied whatever its size: it would have to be copied to be
        /// rebased by whoever reads it, and doing it here is where the block can be let go.
        package init(slicing range: Range<Int>, of block: Data) {
            let shares =
                range.lowerBound == .zero
                && block.startIndex == .zero
                && range.count >= block.count / Self.sharingThreshold

            if shares {
                self.data = block[range]
            } else {
                self.data = block.subdata(in: range)
            }
        }

        #if canImport(NIOCore)
        /// The bytes of `buffer`, as `Data` that starts at index zero.
        ///
        /// `.automatic` rather than `.copy`: past 256 KiB it hands out the bytes without copying
        /// them, keeping the buffer's storage alive for as long as the chunk lives. That is safe
        /// here because the buffer is a value, copy on write, so nobody can change the bytes under
        /// the chunk; a writer to the buffer would copy first. The cost is that the chunk then
        /// holds the whole allocation, which is what the chunk is, for a piece this large.
        /// Anything smaller is copied, exactly as `.copy` would.
        package init(_ buffer: NIOCore.ByteBuffer) {
            self.init(
                buffer.getData(
                    at: buffer.readerIndex,
                    length: buffer.readableBytes,
                    byteTransferStrategy: .automatic
                ) ?? Data()
            )
        }
        #endif

        // MARK: - Internal properties

        /// What fraction of a block a slice of it has to be, as the divisor: one half.
        package static let sharingThreshold = 2
    }
}
