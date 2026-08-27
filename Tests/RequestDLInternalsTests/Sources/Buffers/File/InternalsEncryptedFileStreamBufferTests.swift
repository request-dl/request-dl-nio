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

struct InternalsEncryptedFileStreamBufferTests {

    private let chunkPlaintextSize = Internals.EncryptedFileStreamBuffer.chunkPlaintextSize

    private func makeURL(_ fileURL: URL, key: SymmetricKey = .init(size: .bits256)) -> Internals.EncryptedFileBufferURL {
        .init(inner: .init(fileURL), key: key)
    }

    @Test
    func writeThenRead_whenContentSpansMultipleChunks_shouldRoundTrip() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let expected = Data((0..<(chunkPlaintextSize * 2 + 12_345)).map { UInt8($0 % 256) })
            let url = makeURL(fileURL)

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            await writer.writeData(expected)
            try await writer.close()

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            let read = await reader.getData()

            #expect(read == expected)
        }
    }

    @Test
    func writeThenRead_whenContentIsEmpty_shouldRoundTripToEmptyData() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            let writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            try await writer.close()

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)

            // Then: an empty resource still round-trips to zero readable bytes — `writtenBytes`
            // correctly reports the (empty) plaintext content, not the header-plus-tag bytes the
            // real file carries. `getData()` itself answers `nil` here rather than `Data()`,
            // matching `Internals.FileStreamBuffer.readData(length:)`'s own `length > .zero`
            // guard — an existing invariant of this whole buffer stack for any zero-byte
            // resource, encrypted or not, not something specific to this type.
            #expect(reader.readableBytes == .zero)
            #expect(await reader.getData() == nil)
        }
    }

    @Test
    func writtenBytes_shouldReportPlaintextCountNotCiphertextCount() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let expected = Data(repeating: 0x2A, count: 10_000)
            let url = makeURL(fileURL)

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            await writer.writeData(expected)
            try await writer.close()

            let rawSize = await Internals.FileBufferURL(fileURL).writtenBytes
            let plaintextSize = await url.writtenBytes

            // Then: the buffer's own accounting matches what was actually written, not the
            // (larger) real file, which carries the header and per-chunk tag overhead on top.
            #expect(plaintextSize == expected.count)
            #expect(rawSize > plaintextSize)
        }
    }

    @Test
    func read_whenSingleByteFlipped_shouldFailAsDecryptionMiss() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            await writer.writeData(Data("Hello, encrypted world!".utf8))
            try await writer.close()

            var raw = try Data(contentsOf: fileURL)
            let tamperIndex = raw.count - 1
            raw[tamperIndex] ^= 0xFF
            try raw.write(to: fileURL)

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            let read = await reader.getData()

            #expect(read == nil)
        }
    }

    @Test
    func read_whenChunksAreReordered_shouldFailAsDecryptionMiss() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            // Given: three whole non-final chunks, plus whatever `close()` flushes as the final
            // one — enough for two full, independently addressable non-final chunks to swap.
            let expected = Data((0..<(chunkPlaintextSize * 3)).map { UInt8($0 % 256) })

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            await writer.writeData(expected)
            try await writer.close()

            let headerSize = 13
            let chunkOnDiskSize = chunkPlaintextSize + 16

            var raw = try Data(contentsOf: fileURL)
            let firstChunkRange = headerSize..<(headerSize + chunkOnDiskSize)
            let secondChunkRange = (headerSize + chunkOnDiskSize)..<(headerSize + chunkOnDiskSize * 2)

            let firstChunk = raw[firstChunkRange]
            let secondChunk = raw[secondChunkRange]
            raw.replaceSubrange(firstChunkRange, with: secondChunk)
            raw.replaceSubrange(secondChunkRange, with: firstChunk)
            try raw.write(to: fileURL)

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            let read = await reader.getData()

            // Then: each chunk's associated data binds its own index, so a chunk decrypted at
            // another chunk's position fails its tag check rather than silently reordering.
            #expect(read == nil)
        }
    }

    @Test
    func read_whenTrailingChunkIsTruncated_shouldFailAsDecryptionMiss() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let url = makeURL(fileURL)

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            await writer.writeData(Data("Hello, encrypted world!".utf8))
            try await writer.close()

            var raw = try Data(contentsOf: fileURL)
            raw.removeLast(4)
            try raw.write(to: fileURL)

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            let read = await reader.getData()

            #expect(read == nil)
        }
    }

    @Test
    func read_whenOpenedWithWrongKey_shouldFailAsDecryptionMissNotCrash() async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            let writeKey = SymmetricKey(size: .bits256)
            let readKey = SymmetricKey(size: .bits256)

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(
                addressing: makeURL(fileURL, key: writeKey)
            )
            await writer.writeData(Data("Hello, encrypted world!".utf8))
            try await writer.close()

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(
                addressing: makeURL(fileURL, key: readKey)
            )
            let read = await reader.getData()

            #expect(read == nil)
        }
    }

    /// Mirrors `InternalsFileStreamBufferTests`' identical stress test — many independent
    /// instances, each with its own file and lock, exercising the cooperative-pool-saturation
    /// shape that made disk-backed buffer writes flaky under `swift-testing`'s parallel execution
    /// before offloading to `NIOThreadPool`.
    @Test
    func manyInstances_whenRunningConcurrently_shouldAllCompleteWithoutStallingTheCooperativePool() async throws {
        let expected = Data(repeating: 0x2A, count: 4_096)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    try await withTemporaryFileURL("encrypted.bin") { fileURL in
                        let url = self.makeURL(fileURL)

                        var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
                        await writer.writeData(expected)
                        try await writer.close()

                        let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
                        let read = await reader.getData()

                        #expect(read == expected)
                    }
                }
            }

            try await group.waitForAll()
        }
    }
}
