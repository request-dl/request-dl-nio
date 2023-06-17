/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InternalsBodyTests: XCTestCase {

    func testRequestBody_whenFragmentByOne_shouldContainsAllCharacters() async throws {
        // Given
        let string = "Hello World"

        let body = Internals.Body(buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        XCTAssertEqual(body.chunkSize, 1)
        XCTAssertEqual(body.totalSize, string.count)

        XCTAssertEqual(
            buffers.resolveData(),
            Array(string.utf8).split(by: 1)
        )
    }

    func testRequestBody_whenSizeIsSpecified_shouldContainsString() async throws {
        // Given
        let string = "Hello World"

        let body = Internals.Body(chunkSize: string.count, buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        XCTAssertEqual(body.chunkSize, string.count)
        XCTAssertEqual(body.totalSize, string.count)

        XCTAssertEqual(
            buffers.resolveData(),
            [Data(string.utf8)]
        )
    }

    func testRequestBody_whenDataIsEmpty() async throws {
        // Given
        let string = ""

        let body = Internals.Body(buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        XCTAssertEqual(body.chunkSize, .zero)
        XCTAssertEqual(body.totalSize, string.count)

        XCTAssertEqual(
            buffers.resolveData(),
            []
        )
    }

    func testRequestBody_whenEmptyBuffer() async throws {
        // Given
        let body = Internals.Body(buffers: [])

        // When
        let buffers = try await body.buffers()

        // Then
        XCTAssertEqual(body.chunkSize, .zero)
        XCTAssertEqual(body.totalSize, .zero)

        XCTAssertEqual(
            buffers.resolveData(),
            []
        )
    }
}
