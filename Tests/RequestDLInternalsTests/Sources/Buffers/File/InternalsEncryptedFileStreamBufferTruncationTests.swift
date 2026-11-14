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

/// A writer killed before `close()` leaves the header plus however many full chunks it had
/// already flushed (the rest only ever lived in memory), with no authenticated final chunk. The
/// reader has to treat that as unreadable, whatever shape the cut takes.
struct InternalsEncryptedFileStreamBufferTruncationTests {

    private let chunkPlaintextSize = Internals.EncryptedFileStreamBuffer.chunkPlaintextSize
    private let headerSize = 13
    private let tagSize = 16

    private var chunkOnDiskSize: Int { chunkPlaintextSize + tagSize }

    private func makeURL(_ fileURL: URL) -> Internals.EncryptedFileBufferURL {
        .init(inner: .init(fileURL), key: .init(size: .bits256))
    }

    /// Writes `body` through a real writer, then cuts the file down to `rawSize(...)` bytes.
    private func writeAndCut(
        _ body: Data,
        to fileURL: URL,
        url: Internals.EncryptedFileBufferURL,
        keeping rawSize: (_ fullSize: Int) -> Int
    ) async throws {
        var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
        await writer.writeData(body)
        try await writer.close()

        let raw = try Data(contentsOf: fileURL)
        let kept = rawSize(raw.count)
        #expect(kept <= raw.count)
        try raw.prefix(kept).write(to: fileURL)
    }

    private func body(chunks: Int, extra: Int) -> Data {
        Data((0..<(chunkPlaintextSize * chunks + extra)).map { UInt8($0 % 251) })
    }

    // MARK: - A cut after k whole chunks

    /// The cut the audit reproduced: exactly header plus two sealed (`isLast: false`) chunks,
    /// and a few bytes more or none at all.
    @Test(arguments: [0, 1, 5, 15])
    func getData_whenFileEndsRightAfterWholeChunks_shouldBeAMiss(_ strayBytes: Int) async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            try await writeAndCut(body(chunks: 2, extra: 12_345), to: fileURL, url: url) { _ in
                headerSize + chunkOnDiskSize * 2 + strayBytes
            }

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)

            #expect(await reader.getData() == nil)
        }
    }

    /// Nothing may come back for the first piece either: `CacheControl` serves a hit only after
    /// the first read succeeds, so a stream that hands out chunk 0 and fails later is a response
    /// that dies halfway instead of a clean miss.
    @Test(arguments: [0, 5])
    func readData_whenFileEndsRightAfterWholeChunks_shouldFailBeforeReturningAnything(_ strayBytes: Int) async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            try await writeAndCut(body(chunks: 2, extra: 12_345), to: fileURL, url: url) { _ in
                headerSize + chunkOnDiskSize * 2 + strayBytes
            }

            let reader = try await Internals.EncryptedFileStreamBuffer(readingFrom: url)

            await #expect(throws: (any Error).self) {
                _ = try await reader.readData(length: UInt64(chunkPlaintextSize))
            }

            try await reader.close()
        }
    }

    @Test
    func writtenBytes_whenFileEndsRightAfterWholeChunks_shouldReportNothingReadable() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            try await writeAndCut(body(chunks: 2, extra: 12_345), to: fileURL, url: url) { _ in
                headerSize + chunkOnDiskSize * 2
            }

            #expect(await url.writtenBytes == 0)
        }
    }

    // MARK: - A cut inside a chunk

    @Test
    func getData_whenCutInsideTheFinalChunk_shouldBeAMiss() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            try await writeAndCut(body(chunks: 2, extra: 12_345), to: fileURL, url: url) { _ in
                headerSize + chunkOnDiskSize * 2 + 100
            }

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)

            #expect(await reader.getData() == nil)
        }
    }

    @Test
    func getData_whenCutInsideAnEarlierChunk_shouldBeAMiss() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            try await writeAndCut(body(chunks: 2, extra: 12_345), to: fileURL, url: url) { _ in
                headerSize + chunkOnDiskSize + 1_000
            }

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)

            #expect(await reader.getData() == nil)
        }
    }

    @Test
    func getData_whenOnlyTheFinalChunkWasDropped_shouldBeAMiss() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            // Given: header plus one whole chunk, cut where a *valid* single-chunk file could not
            // end (it would carry its own, `isLast`, chunk after that).
            try await writeAndCut(body(chunks: 1, extra: 700), to: fileURL, url: url) { _ in
                headerSize + chunkOnDiskSize
            }

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)

            #expect(await reader.getData() == nil)
        }
    }

    // MARK: - Intact files still read

    @Test(arguments: [0, 1, 12_345, 4 * 1_024 * 1_024 - 1])
    func getData_whenFileIsIntact_shouldReadEverything(_ extra: Int) async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)
            let expected = body(chunks: 2, extra: extra)

            try await writeAndCut(expected, to: fileURL, url: url) { $0 }

            #expect(await url.writtenBytes == expected.count)

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)

            #expect(await reader.getData() == expected)
        }
    }

    @Test(arguments: [1, 2, 3])
    func getData_whenBodyIsAnExactMultipleOfTheChunk_shouldReadEverything(_ chunks: Int) async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)
            let expected = body(chunks: chunks, extra: 0)

            try await writeAndCut(expected, to: fileURL, url: url) { $0 }

            // The empty final chunk still contributes its tag.
            let raw = try Data(contentsOf: fileURL)
            #expect(raw.count == headerSize + chunkOnDiskSize * chunks + tagSize)

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)

            #expect(await reader.getData() == expected)
        }
    }

    @Test
    func getData_whenFileHoldsAnEmptyBody_shouldNotCrashAndReadNothing() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            await writer.writeData(Data())
            try await writer.close()

            #expect(await url.writtenBytes == 0)

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)

            #expect(await reader.getData() == nil)
        }
    }

    /// Only the header made it to disk: no chunk at all, so no final chunk either.
    @Test(arguments: [0, 1, 13, 20, 28])
    func getData_whenFileIsShorterThanAnEmptyBody_shouldBeAMissNotACrash(_ rawSize: Int) async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            try await writeAndCut(Data("hello".utf8), to: fileURL, url: url) { _ in rawSize }

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)

            #expect(await reader.getData() == nil)
        }
    }

    // MARK: - Plaintext size

    @Test
    func plaintextSize_forEveryShapeAroundAChunkBoundary_neverCountsAnUnauthenticatedChunk() {
        let size = Internals.EncryptedFileStreamBuffer.plaintextSize(fromRawSize:)

        // A valid file ends with a block of `tag ..< chunkOnDiskSize` bytes after its whole chunks.
        for chunks in 0...2 {
            let base = headerSize + chunkOnDiskSize * chunks

            #expect(size(base + tagSize) == chunkPlaintextSize * chunks)
            #expect(size(base + tagSize + 100) == chunkPlaintextSize * chunks + 100)
            #expect(size(base + chunkOnDiskSize - 1) == chunkPlaintextSize * (chunks + 1) - 1)

            // A block of zero bytes, or of fewer than a tag, carries no final chunk.
            if chunks > 0 {
                #expect(size(base) == 0)
                #expect(size(base + tagSize - 1) == 0)
            }
        }

        #expect(size(0) == 0)
        #expect(size(headerSize) == 0)
        #expect(size(headerSize + tagSize - 1) == 0)
    }
}
