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

    /// On a 32-bit platform `Int.max` is 2 GiB: a size past it is not clamped, which reports a file
    /// shorter than it is and lets a reader end its stream as if the body were whole.
    @Test(arguments: [(0, 0), (1, 1), (100, 100), (101, 0), (Int64(Int32.max) + 1, 0), (-1, 0)] as [(Int64, Int)])
    func aSizeThatDoesNotFitAnInt_isUnreadable(_ size: Int64, _ expected: Int) {
        // Given: an `Int` of 100, in place of a 32-bit one
        // When
        let bytes = Internals.FileBufferURL.readableSize(ofFileSized: size, limit: 100)

        // Then
        #expect(bytes == expected)
    }

    @Test
    func theSizeOfAFile_isItsWrittenBytes() {
        #expect(Internals.FileBufferURL.readableSize(ofFileSized: 5) == 5)
        #expect(Internals.FileBufferURL.readableSize(ofFileSized: Int64(Int.max)) == Int.max)
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
    func removeIfTemporaryDeletesATemporaryFile() async throws {
        // Given
        let bufferURL = Internals.FileBufferURL.temporaryURL
        try await bufferURL.absoluteURL().createPathIfNeeded()
        #expect(await bufferURL.isResourceAvailable())

        // When
        await bufferURL.removeIfTemporary()

        // Then
        #expect(await !bufferURL.isResourceAvailable())
    }

    /// A request that is cancelled cleans up from a cancelled Task, and `NIOFileSystem` refuses
    /// work there, so the removal must not depend on the Task it runs in.
    @Test
    func removeIfTemporaryDeletesTheFileFromACancelledTask() async throws {
        // Given
        let bufferURL = Internals.FileBufferURL.temporaryURL
        try await bufferURL.absoluteURL().createPathIfNeeded()
        #expect(await bufferURL.isResourceAvailable())

        // When
        let cleanup = Task {
            while !Task.isCancelled {
                await Task.yield()
            }

            await bufferURL.removeIfTemporary()
        }

        cleanup.cancel()
        await cleanup.value

        // Then
        #expect(await !bufferURL.isResourceAvailable())
    }

    @Test
    func removeIfTemporaryKeepsAFileThisPackageDidNotCreate() async throws {
        try await withTemporaryFileURL("not-temporary.bin") { url in
            // Given
            try await url.write(Data("keep".utf8))
            let bufferURL = Internals.FileBufferURL(url)

            // When
            await bufferURL.removeIfTemporary()

            // Then
            #expect(await bufferURL.isResourceAvailable())
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
