//
// See LICENSE for this package's licensing information.
//

import Crypto
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

struct InternalsEncryptedFileBufferURLTests {

    @Test
    func writtenBytes_whenBodyIsExactMultipleOfChunkSize_shouldStillTreatLastBlockAsFinal() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let chunkPlaintextSize = Internals.EncryptedFileStreamBuffer.chunkPlaintextSize
            let url = Internals.EncryptedFileBufferURL(inner: .init(fileURL), key: .init(size: .bits256))

            // Given: a body that divides evenly into two full chunks — `close()` still flushes
            // one extra, empty, `isLast=true` chunk on top, so the on-disk layout never has a
            // "coincidentally full-size" final block to disambiguate.
            let expected = Data(repeating: 0x2A, count: chunkPlaintextSize * 2)

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            await writer.writeData(expected)
            try await writer.close()

            let plaintextSize = await url.writtenBytes
            #expect(plaintextSize == expected.count)

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            let read = await reader.getData()
            #expect(read == expected)
        }
    }

    /// Regression coverage: a body that is an exact multiple of the *on-disk* chunk size
    /// (`chunkPlaintextSize + 16` byte tag) -- unlike the test above, whose body divides evenly
    /// into `chunkPlaintextSize` but still carries a genuine empty final chunk's 16-byte tag on
    /// top -- can never come from a properly closed writer (see `plaintextSize(fromRawSize:)`'s
    /// own doc comment). It is exactly what a writer that flushed full intermediate chunks and
    /// then crashed before `close()` ever ran leaves behind. `plaintextSize(fromRawSize:)` used
    /// to treat the last of those on-disk chunks as if it were a genuine, `isLast`-flagged final
    /// chunk, over-reporting by a full `chunkPlaintextSize` -- important because
    /// `Internals.CacheControl.isCachedDataValid` compares this exact value against the origin's
    /// `Content-Length` to decide whether a cache entry is complete, so an inflated size here
    /// could make a truncated cache entry look complete.
    @Test
    func writtenBytes_whenBodyIsExactMultipleOfChunkOnDiskSize_reportsOnlyTheGenuinelyReadableChunks() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let chunkPlaintextSize = Internals.EncryptedFileStreamBuffer.chunkPlaintextSize
            let url = Internals.EncryptedFileBufferURL(inner: .init(fileURL), key: .init(size: .bits256))

            // Given: three full chunks, properly closed -- so the real on-disk file is three full
            // chunks plus a genuine, empty, `isLast=true` final chunk (contributing only its
            // 16-byte tag). Removing exactly those trailing 16 bytes reproduces the on-disk shape
            // of a writer that flushed three full intermediate chunks and crashed before `close()`
            // ever ran: a body that is an exact multiple of the on-disk chunk size, with no
            // authenticated final chunk at all.
            let expected = Data((0..<(chunkPlaintextSize * 3)).map { UInt8($0 % 256) })

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            await writer.writeData(expected)
            try await writer.close()

            let headerSize = 13
            let tagSize = 16
            let chunkOnDiskSize = chunkPlaintextSize + tagSize

            var raw = try Data(contentsOf: fileURL)
            #expect(raw.count == headerSize + chunkOnDiskSize * 3 + tagSize)
            raw.removeLast(tagSize)
            try raw.write(to: fileURL)

            // Then: only the first two chunks are genuinely readable. The third now sits exactly
            // at the truncated file's end, so it gets misread as the final chunk (`isLast: true`)
            // even though it was actually sealed as `isLast: false` -- its own tag check would
            // fail were it ever attempted, so its `chunkPlaintextSize` bytes must not be counted.
            let plaintextSize = await url.writtenBytes
            #expect(plaintextSize == chunkPlaintextSize * 2)
        }
    }

    /// `init(addressing:)` retries a zero-byte size stat 30 times, 10ms apart, to close a reopen
    /// race: the same encrypted file's writer and reader are two distinct `Buffer`/`Storage`
    /// pairs, and the reader's very first stat has been caught reporting zero for a file the
    /// writer had already closed.
    ///
    /// `DiskStorage.allocateBuffer` reaches the same initializer for the opposite case — it has
    /// just created the file and knows nothing is in it yet — where the loop could only ever
    /// exhaust its whole budget, putting a fixed ~290ms of sleeping in front of every encrypted
    /// cache write.
    @available(iOS 16, tvOS 16, watchOS 9, macOS 13, *)
    @Test
    func addressing_whenContentIsKnownToBeEmpty_shouldNotPayTheReopenRetryBudget() async throws {
        try await withTemporaryFileURL("empty.bin") { fileURL in
            let url = Internals.EncryptedFileBufferURL(inner: .init(fileURL), key: .init(size: .bits256))
            let clock = ContinuousClock()

            // Given: the same legitimately-empty file opened the way the read path does, which
            // has no way to tell "empty" from "the stat flake" and pays the budget in full.
            let retryingStart = clock.now
            _ = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            let retryingElapsed = clock.now - retryingStart

            // When: opened the way a write that created the file itself does.
            let directStart = clock.now
            _ = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(
                addressing: url,
                retryingEmptyContent: false
            )
            let directElapsed = clock.now - directStart

            // Then: one stat, not thirty with sleeps between them. Measured against each other
            // rather than against a fixed threshold, since both sides absorb the same machine
            // contention while only one of them carries the extra ~290ms.
            #expect(directElapsed * 2 < retryingElapsed)
        }
    }

    @Test
    func make_fromFoundationURL_shouldReturnNil() {
        let url = Internals.EncryptedFileBufferURL.make(from: URL(fileURLWithPath: "/tmp/whatever"))
        #expect(url == nil)
    }
}
