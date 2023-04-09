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
        XCTAssertEqual(
            buffers.resolveData(),
            Array(string.utf8).split(by: 1)
        )
    }

    func testRequestBody_whenSizeIsSpecified_shouldContainsString() async throws {
        // Given
        let string = "Hello World"

        let body = Internals.Body(string.count, buffers: [
            Internals.DataBuffer(string)
        ])

        // When
        let buffers = try await body.buffers()

        // Then
        XCTAssertEqual(
            buffers.resolveData(),
            [Data(string.utf8)]
        )
    }
}
