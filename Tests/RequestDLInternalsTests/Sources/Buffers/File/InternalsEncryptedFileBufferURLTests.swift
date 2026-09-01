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

    @Test
    func make_fromFoundationURL_shouldReturnNil() {
        let url = Internals.EncryptedFileBufferURL.make(from: URL(fileURLWithPath: "/tmp/whatever"))
        #expect(url == nil)
    }
}
