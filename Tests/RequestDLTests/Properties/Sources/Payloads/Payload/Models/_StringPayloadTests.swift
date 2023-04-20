/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class _StringPayloadTests: XCTestCase {

    func testStringPayload() async throws {
        // Given
        let foo = "foo"

        // When
        let payload = _StringPayload(foo, using: .utf8)
        let expectedData = Data(foo.utf8)

        // Then
        XCTAssertEqual(payload.buffer, Internals.DataBuffer(expectedData))
    }
}
