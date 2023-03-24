/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDLInternals

class RequestBodyTests: XCTestCase {

    func testRequestBody_whenFragmentByOne_shouldContainsAllCharacters() async throws {
        // Given
        let string = "Hello World"

        let body = RequestBody {
            BodyItem(string)
        }

        // When
        var buffers = try await body.buffers()

        // Then
        XCTAssertEqual(
            buffers.resolveData(),
            Array(string.utf8).split(by: 1)
        )
    }

    func testRequestBody_whenSizeIsSpecified_shouldContainsString() async throws {
        // Given
        let string = "Hello World"

        let body = RequestBody(string.count) {
            BodyItem(string)
        }

        // When
        let buffers = try await body.buffers()

        // Then
        XCTAssertEqual(
            buffers.resolveData(),
            [Data(string.utf8)]
        )
    }
}
