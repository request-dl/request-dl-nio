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

        /// The exact disk record directory `diskBuffer` writes into, `nil` when there is no
        /// disk tier (memory-only policy, or the disk write couldn't be allocated). Kept around
        /// so a caller whose body stream never finishes writing through this buffer can hand it
        /// straight to ``DataCache/discardFailedWrite(_:forKey:)`` — precise cleanup of exactly
        /// this write, not a search by key that could catch an unrelated, still in-progress
        /// write to the same key from a concurrent request.
        let diskRecordURL: URL?

        // MARK: - Private properties

        private var memoryBuffer: Internals.AnyBuffer?
        private var diskBuffer: Internals.AnyBuffer?

        // MARK: - Inits

        init(
            memoryBuffer: Internals.AnyBuffer?,
            diskBuffer: Internals.AnyBuffer?,
            diskRecordURL: URL? = nil
        ) {
            self.memoryBuffer = memoryBuffer
            self.diskBuffer = diskBuffer
            self.diskRecordURL = diskRecordURL
        }

        // MARK: - Internal methods

        mutating func writeBuffer(_ buffer: Internals.AnyBuffer) async {
            guard let bytes = await buffer.getBytes() else {
                return
            }

            await memoryBuffer?.writeBytes(bytes)
            await diskBuffer?.writeBytes(bytes)
        }
    }
}
