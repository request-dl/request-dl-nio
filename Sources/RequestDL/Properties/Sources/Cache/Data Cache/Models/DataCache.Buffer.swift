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

        /// A tier of the cache.
        enum Tier: Sendable {
            case memory
            case disk
        }

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

        /// Whether the memory tier was given up on because the body outgrew its capacity.
        private(set) var memoryOverflowed = false

        /// Whether the disk tier was given up on because the body outgrew its capacity.
        private(set) var diskOverflowed = false

        // MARK: - Private properties

        private var memoryBuffer: Internals.AnyBuffer?
        private var diskBuffer: Internals.AnyBuffer?

        private let memoryCapacity: Int64
        private let diskCapacity: Int64
        private var memoryWritten: Int64 = 0
        private var diskWritten: Int64 = 0

        /// Removes what a tier holds of this write, called once, when the body outgrows it.
        private let onOverflow: (@Sendable (Tier) async -> Void)?

        // MARK: - Inits

        init(
            memoryBuffer: Internals.AnyBuffer?,
            diskBuffer: Internals.AnyBuffer?,
            diskRecordURL: URL? = nil,
            memoryDataURL: Internals.ByteURL? = nil,
            writeToken: DataCache.WriteToken? = nil,
            memoryCapacity: Int64 = .max,
            diskCapacity: Int64 = .max,
            onOverflow: (@Sendable (Tier) async -> Void)? = nil
        ) {
            self.memoryBuffer = memoryBuffer
            self.diskBuffer = diskBuffer
            self.diskRecordURL = diskRecordURL
            self.memoryDataURL = memoryDataURL
            self.writeToken = writeToken
            self.memoryCapacity = memoryCapacity
            self.diskCapacity = diskCapacity
            self.onOverflow = onOverflow
        }

        // MARK: - Internal methods

        mutating func writeBuffer(_ buffer: Internals.AnyBuffer) async {
            guard let bytes = await buffer.getBytes() else {
                return
            }

            let count = Int64(bytes.count)

            // A tier is admitted a write by the response's `Content-Length`, which is 0 when there
            // is none (a chunked response), and the body is not bounded by that hint. Counting
            // what is actually written, a tier the body outgrows is given up on at that point,
            // instead of holding the whole body until a later write evicts it.
            if memoryBuffer != nil {
                memoryWritten += count

                if memoryWritten > memoryCapacity {
                    memoryBuffer = nil
                    memoryOverflowed = true
                    await onOverflow?(.memory)
                } else {
                    await memoryBuffer?.writeBytes(bytes)
                }
            }

            if diskBuffer != nil {
                diskWritten += count

                if diskWritten > diskCapacity {
                    diskBuffer = nil
                    diskOverflowed = true
                    await onOverflow?(.disk)
                } else {
                    await diskBuffer?.writeBytes(bytes)
                }
            }
        }

        /// Closes the disk buffer, so everything written through it is on disk and, with an
        /// encryption key, the final chunk is sealed. Left to the buffer's own teardown, that
        /// happens after the entry is already being served.
        func closeDiskBuffer() async {
            try? await diskBuffer?.close()
        }
    }
}
