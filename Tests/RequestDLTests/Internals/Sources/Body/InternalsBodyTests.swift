//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsBodyTests {

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
        await #expect(buffers.resolveData() == Array(string.utf8).split(by: string.count))
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

        await #expect(
            buffers.resolveData() == [Data(string.utf8)]
        )
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

        await #expect(
            buffers.resolveData() == []
        )
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

        await #expect(
            buffers.resolveData() == []
        )
    }
}
