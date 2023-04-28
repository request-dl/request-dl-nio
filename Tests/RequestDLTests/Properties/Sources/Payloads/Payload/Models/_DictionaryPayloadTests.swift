/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class _DictionaryPayloadTests: XCTestCase {

    func testDictionaryPayload() async throws {
        // Given
        let data: [String: Any] = [
            "foo": 1,
            "bar": "password"
        ]
        let options = JSONSerialization.WritingOptions([.withoutEscapingSlashes])

        // When
        let payload = _DictionaryPayload(data, options: options)
        let expectedData = try JSONSerialization.data(withJSONObject: data, options: options)

        // Then
        XCTAssertEqual(payload.buffer.getData(), expectedData)
    }
}
