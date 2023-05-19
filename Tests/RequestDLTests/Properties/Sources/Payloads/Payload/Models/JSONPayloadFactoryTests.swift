/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class JSONPayloadFactoryTests: XCTestCase {

    func testDictionaryPayload() async throws {
        // Given
        let data: [String: Any] = [
            "foo": 1,
            "bar": "password"
        ]
        let options = JSONSerialization.WritingOptions([.withoutEscapingSlashes])

        // When
        let payload = JSONPayloadFactory(
            jsonObject: data,
            options: options,
            contentType: nil
        )

        let expectedData = try JSONSerialization.data(withJSONObject: data, options: options)

        // Then
        XCTAssertEqual(try payload().getData(), expectedData)
    }
}
