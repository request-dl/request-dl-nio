/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class DataPayloadFactoryTests: XCTestCase {

    func testDataPayload() async throws {
        // Given
        let data = Data("foo".utf8)
        let contentType = ContentType.octetStream

        // When
        let payload = DataPayloadFactory(
            data: data,
            contentType: contentType
        )

        // Then
        XCTAssertEqual(try payload().getData(), data)
        XCTAssertEqual(payload.contentType, contentType)
    }
}
