/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class StringPayloadFactoryTests: XCTestCase {

    func testStringPayload() async throws {
        // Given
        let foo = "foo"

        // When
        let payload = StringPayloadFactory(
            verbatim: foo,
            encoding: .utf8,
            contentType: .text
        )
        let expectedData = Data(foo.utf8)

        // Then
        XCTAssertEqual(try payload().getData(), expectedData)
    }
}
