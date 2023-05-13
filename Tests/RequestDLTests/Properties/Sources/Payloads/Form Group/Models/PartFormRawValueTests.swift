/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class PartFormRawValueTests: XCTestCase {

    func testInitWithDataAndHeaders() async throws {
        // Given
        let data = "Test data".data(using: .utf8) ?? Data()

        let headers: [String: String] = [
            "Content-Type": "text/plain",
            "Content-Length": "9",
            "Custom-Header": "custom-value"
        ]

        // When
        let part = PartFormRawValue(data, forHeaders: headers)

        // Then
        XCTAssertEqual(part.data, data)
        XCTAssertEqual(part.headers.count, 3)
        XCTAssertEqual(part.headers["Content-Type"], "text/plain")
        XCTAssertEqual(part.headers["Content-Length"], "9")
        XCTAssertEqual(part.headers["Custom-Header"], "custom-value")
    }

    func testContentDispositionValue_withFileName() async throws {
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

    func testContentDispositionValue_withoutFileName() async throws {
        // Given
        let key = "testKey"

        // When
        let contentDisposition = kContentDispositionValue(nil, forKey: key)

        // Then
        XCTAssertEqual(contentDisposition, "form-data; name=\"\(key)\"")
    }
}
