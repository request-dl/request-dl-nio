//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

/// A tier that misses a write is given up on, not written on past the gap: a buffer reports a
/// failed write by its writer not moving, and the next chunk then lands where the failed one was
/// meant to go, which stores a body with a piece of it missing.
struct DataCacheBufferTests {

    private final class Overflowed: @unchecked Sendable {

        var tiers: [DataCache.Buffer.Tier] {
            lock.withLock { _tiers }
        }

        private let lock = SwiftAsyncStream.Lock()
        private var _tiers: [DataCache.Buffer.Tier] = []

        func append(_ tier: DataCache.Buffer.Tier) {
            lock.withLock { _tiers.append(tier) }
        }
    }

    private func chunk(_ byte: UInt8, count: Int = 4) async -> Internals.AnyBuffer {
        await Internals.DataBuffer(Data(repeating: byte, count: count))
    }

    /// A file buffer whose file can never be created: its parent is a file, not a directory.
    ///
    /// `file` is what `withTemporaryFileURL` hands out, a path that exists and is a file.
    private func unwritableBuffer(under file: URL) async -> Internals.AnyBuffer {
        await Internals.FileBuffer(file.appendingPathComponent("child"))
    }

    @Test
    func writeBuffer_whenATierMissesAWrite_givesUpOnItAndRemovesWhatItHeld() async throws {
        try await withTemporaryFileURL { fileURL in
            // Given: a memory tier that works and a disk tier that cannot be written.
            let overflowed = Overflowed()
            let memory = await Internals.DataBuffer(Data())

            var buffer = DataCache.Buffer(
                memoryBuffer: memory,
                diskBuffer: await unwritableBuffer(under: fileURL),
                onOverflow: { overflowed.append($0) }
            )

            // When
            await buffer.writeBuffer(await chunk(0x01))
            await buffer.writeBuffer(await chunk(0x02))

            // Then: the disk tier was given up on at the first chunk, and not written past the gap.
            #expect(overflowed.tiers == [.disk])
            #expect(buffer.diskOverflowed)
            #expect(buffer.memoryOverflowed == false)

            // And the other tier took the whole body.
            #expect(buffer.hasNowhereToWrite == false)
            #expect(buffer.readableBytes == 8)
        }
    }

    @Test
    func writeBuffer_whenEveryTierMissesAWrite_hasNowhereLeftToWrite() async throws {
        try await withTemporaryFileURL { fileURL in
            // Given
            var buffer = DataCache.Buffer(
                memoryBuffer: nil,
                diskBuffer: await unwritableBuffer(under: fileURL)
            )

            // When
            await buffer.writeBuffer(await chunk(0x01))

            // Then: the loop that feeds it stops, instead of reading the rest of the body for nothing.
            #expect(buffer.hasNowhereToWrite)
        }
    }

    @Test
    func writeBuffer_whenNothingMisses_keepsEveryTier() async throws {
        // Given
        let overflowed = Overflowed()

        var buffer = DataCache.Buffer(
            memoryBuffer: await Internals.DataBuffer(Data()),
            diskBuffer: nil,
            onOverflow: { overflowed.append($0) }
        )

        // When
        await buffer.writeBuffer(await chunk(0x01))
        await buffer.writeBuffer(await chunk(0x02))
        await buffer.writeBuffer(await chunk(0x03, count: 0))

        // Then
        #expect(overflowed.tiers.isEmpty)
        #expect(buffer.memoryOverflowed == false)
        #expect(buffer.readableBytes == 8)
    }
}
