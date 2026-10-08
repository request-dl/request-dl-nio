//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

extension DataCache {

    struct Buffer: Sendable {

        var readableBytes: Int {
            (memoryBuffer ?? diskBuffer)?.readableBytes ?? .zero
        }

        /// The exact disk record directory `diskBuffer` writes into, `nil` when there is no disk
        /// tier (memory-only policy, or the disk write couldn't be allocated).
        ///
        /// Lets a caller whose body stream never finishes writing through this buffer hand it to
        /// ``DataCache/discardFailedWrite(_:forKey:)`` for precise cleanup of exactly this write,
        /// instead of a search by key that could catch an unrelated in-progress write.
        let diskRecordURL: URL?

        /// The exact in-memory record `memoryBuffer` writes into, `nil` when there is no memory
        /// tier for this write. `discardFailedWrite(_:forKey:)`'s memory-side counterpart to
        /// `diskRecordURL`: identifies precisely this write's record by reference, not by key, so
        /// discarding it can't delete an unrelated, still-in-progress write to the same key from
        /// a concurrent request.
        let memoryDataURL: Internals.ByteURL?

        /// Keeps the key this write is for out of ``DataCache/getCachedData(forKey:policy:)`` until
        /// the write is finished or discarded. See ``DataCache/WriteToken``.
        let writeToken: DataCache.WriteToken?

        // MARK: - Private properties

        private var memoryBuffer: Internals.AnyBuffer?
        private var diskBuffer: Internals.AnyBuffer?

        // MARK: - Inits

        init(
            memoryBuffer: Internals.AnyBuffer?,
            diskBuffer: Internals.AnyBuffer?,
            diskRecordURL: URL? = nil,
            memoryDataURL: Internals.ByteURL? = nil,
            writeToken: DataCache.WriteToken? = nil
        ) {
            self.memoryBuffer = memoryBuffer
            self.diskBuffer = diskBuffer
            self.diskRecordURL = diskRecordURL
            self.memoryDataURL = memoryDataURL
            self.writeToken = writeToken
        }

        // MARK: - Internal methods

        mutating func writeBuffer(_ buffer: Internals.AnyBuffer) async {
            guard let bytes = await buffer.getBytes() else {
                return
            }

            await memoryBuffer?.writeBytes(bytes)
            await diskBuffer?.writeBytes(bytes)
        }

        /// Closes the disk buffer, so everything written through it is on disk and, with an
        /// encryption key, the final chunk is sealed. Left to the buffer's own teardown, that
        /// happens after the entry is already being served.
        func closeDiskBuffer() async {
            try? await diskBuffer?.close()
        }
    }
}
