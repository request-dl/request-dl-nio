//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsFileBufferURLTests {

    @Test
    func absoluteURLReturnsTheOriginalURL() {
        // Given
        let url = temporaryDirectoryURL.appendingPathComponent("some-file")

        // When
        let bufferURL = Internals.FileBufferURL(url)

        // Then
        #expect(bufferURL.absoluteURL() == url)
    }

    @Test
    func truncateEmptiesAnExistingFile() async throws {
        try await withTemporaryFileURL("truncate.bin") { url in
            // Given
            try await url.write(Data("hello".utf8))
            let bufferURL = Internals.FileBufferURL(url)
            #expect(await bufferURL.writtenBytes == 5)

            // When
            await bufferURL.truncate()

            // Then
            #expect(await bufferURL.writtenBytes == 0)
        }
    }

    @Test
    func truncateOnMissingFileIsANoOp() async throws {
        try await withTemporaryFileURL("missing.bin", createPath: false) { url in
            // Given
            let bufferURL = Internals.FileBufferURL(url)
            #expect(await bufferURL.isResourceAvailable() == false)

            // When / Then (no crash, no file created as a side effect)
            await bufferURL.truncate()
            #expect(await bufferURL.isResourceAvailable() == false)
        }
    }
}
