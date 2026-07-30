/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsBodyTests {

    @Test
    func requestBody_whenSmallBody_shouldSendItInASingleChunk() async throws {
        // Given
        let string = "Hello World"
        let body = RequestBody(buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.totalSize == string.count)

        // Anything under the minimum chunk goes out whole. Eleven characters used to become
        // eleven writes, each with its own future and its own progress event.
        #expect(body.chunkSize == string.count)
        #expect(buffers.resolveData() == Array(string.utf8).split(by: string.count))
    }

    @Test
    func requestBody_whenSizeIsSpecified_shouldContainsString() async throws {
        // Given
        let string = "Hello World"

        let body = RequestBody(chunkSize: string.count, buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.chunkSize == string.count)
        #expect(body.totalSize == string.count)

        #expect(
            buffers.resolveData() == [Data(string.utf8)]
        )
    }

    @Test
    func requestBody_whenDataIsEmpty() async throws {
        // Given
        let string = ""

        let body = RequestBody(buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.chunkSize == .zero)
        #expect(body.totalSize == string.count)

        #expect(
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

        #expect(
            buffers.resolveData() == []
        )
    }
}
