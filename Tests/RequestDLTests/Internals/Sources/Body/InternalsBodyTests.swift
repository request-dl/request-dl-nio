/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsBodyTests {

    @Test
    func requestBody_whenFragmentByOne_shouldContainsAllCharacters() async throws {
        // Given
        let string = "Hello World"

        let body = Internals.Body(buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.chunkSize == 1)
        #expect(body.totalSize == string.count)

        #expect(
            buffers.resolveData(),
            Array(string.utf8).split(by: 1)
        )
    }

    @Test
    func requestBody_whenSizeIsSpecified_shouldContainsString() async throws {
        // Given
        let string = "Hello World"

        let body = Internals.Body(chunkSize: string.count, buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.chunkSize == string.count)
        #expect(body.totalSize == string.count)

        #expect(
            buffers.resolveData(),
            [Data(string.utf8)]
        )
    }

    @Test
    func requestBody_whenDataIsEmpty() async throws {
        // Given
        let string = ""

        let body = Internals.Body(buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.chunkSize == .zero)
        #expect(body.totalSize == string.count)

        #expect(
            buffers.resolveData(),
            []
        )
    }

    @Test
    func requestBody_whenEmptyBuffer() async throws {
        // Given
        let body = Internals.Body(buffers: [])

        // When
        let buffers = try await body.buffers()

        // Then
        #expect(body.chunkSize == .zero)
        #expect(body.totalSize == .zero)

        #expect(
            buffers.resolveData(),
            []
        )
    }
}
