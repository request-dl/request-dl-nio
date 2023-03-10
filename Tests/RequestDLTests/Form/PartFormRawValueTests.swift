/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class PartFormRawValueTests: XCTestCase {

    func testInitWithDataAndHeaders() throws {
        // Given
        let data = "Test data".data(using: .utf8) ?? Data()

        let headers: [String: Any] = [
            "Content-Type": "text/plain",
            "Content-Length": 9,
            "Custom-Header": "custom-value"
        ]

        // When
        let part = PartFormRawValue(data, forHeaders: headers)

        // Then
        XCTAssertEqual(part.data, data)
        XCTAssertEqual(part.headers.count, 3)
        XCTAssertEqual(part.headers["Content-Type"] as? String, "text/plain")
        XCTAssertEqual(part.headers["Content-Length"] as? Int, 9)
        XCTAssertEqual(part.headers["Custom-Header"] as? String, "custom-value")
    }

    func testContentDispositionValue_withFileName() {
        // Given
        let key = "testKey"
        let fileName = "testFile.txt"

        // When
        let contentDisposition = kContentDispositionValue(fileName, forKey: key)

        // Then
        XCTAssertEqual(
            contentDisposition,
            "form-data; name=\"\(key)\"; filename=\"\(fileName)\""
        )
    }

    func testContentDispositionValue_withoutFileName() {
        // Given
        let key = "testKey"

        // When
        let contentDisposition = kContentDispositionValue(nil, forKey: key)

        // Then
        XCTAssertEqual(contentDisposition, "form-data; name=\"\(key)\"")
    }
}
