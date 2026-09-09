//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
import struct Foundation.UUID
#endif

struct RequestBodyBuildingTests {

    @Test
    func requestBody_whenSmallBody_shouldSendItInASingleChunk() async throws {
        // Given
        let string = "Hello World"
        let body = await RequestBody(buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.totalSize == string.count)

        // Regression guard: anything under the minimum chunk must go out whole, not as one
        // write per character, each with its own future and its own progress event.
        #expect(body.chunkSize == string.count)
        let resolvedData = await buffers.resolveData()
        let expectedChunks = await Array(string.utf8).split(by: string.count)
        #expect(resolvedData == expectedChunks)
    }

    @Test
    func requestBody_whenSizeIsSpecified_shouldContainsString() async throws {
        // Given
        let string = "Hello World"

        let body = await RequestBody(
            chunkSize: string.count,
            buffers: [
                Internals.DataBuffer(string)
            ]
        )

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.chunkSize == string.count)
        #expect(body.totalSize == string.count)

        let resolvedData = await buffers.resolveData()
        #expect(resolvedData == [Data(string.utf8)])
    }

    @Test
    func requestBody_whenDataIsEmpty() async throws {
        // Given
        let string = ""

        let body = await RequestBody(buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.chunkSize == .zero)
        #expect(body.totalSize == string.count)

        let resolvedData = await buffers.resolveData()
        #expect(resolvedData == [])
    }

    @Test
    func requestBody_whenEmptyBuffer() async throws {
        // Given
        let body = RequestBody(buffers: [])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.chunkSize == .zero)
        #expect(body.totalSize == .zero)

        let resolvedData = await buffers.resolveData()
        #expect(resolvedData == [])
    }

    @Test
    func requestBody_whenBackedByASingleUnreadFile_wholeFileURLReturnsThatFile() async throws {
        // Given -- forwards straight to `Internals.BodySequence.wholeFileURL`; see
        // `InternalsBodySequenceTests`/`InternalsFileBufferTests` for the underlying-buffer-level
        // coverage of what "qualifies" means. This test only confirms `RequestBody` itself
        // forwards it, since `Internals.URLSessionClient+RequestExecutingClient.swift` reads it
        // off `RequestBody`, not `Internals.BodySequence`, directly.
        let url =
            temporaryDirectoryURL
            .appendingPathComponent("requestBody.\(UUID())")
            .appendingPathExtension("raw")
        try await url.createPathIfNeeded()
        defer { url.scheduleRemoval() }
        try Data("Hello world".utf8).write(to: url)

        let body = await RequestBody(buffers: [Internals.FileBuffer(url)])

        // Then
        #expect(body.wholeFileURL == url)
    }

    @Test
    func requestBody_whenBackedByData_wholeFileURLReturnsNil() async throws {
        // Given
        let body = await RequestBody(buffers: [Internals.DataBuffer("Hello world")])

        // Then
        #expect(body.wholeFileURL == nil)
    }
}
