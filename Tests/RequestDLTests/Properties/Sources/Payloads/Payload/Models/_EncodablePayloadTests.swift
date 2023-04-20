/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class _EncodablePayloadTests: XCTestCase {

    struct Mock: Codable {
        let foo: String
        let date: Date
    }

    func testEncodablePayload() async throws {
        // Given
        let mock = Mock(
            foo: "foo",
            date: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        // When
        let payload = _EncodablePayload(mock, encoder: encoder)
        let expectedData = try encoder.encode(mock)
        let expectedMock = try decoder.decode(Mock.self, from: expectedData)

        // Then
        XCTAssertEqual(payload.buffer.getData(), expectedData)
        XCTAssertEqual(mock.foo, expectedMock.foo)

        XCTAssertEqual(
            mock.date.seconds,
            expectedMock.date.seconds
        )
    }
}
