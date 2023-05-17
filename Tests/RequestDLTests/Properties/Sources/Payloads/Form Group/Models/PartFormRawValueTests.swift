/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class PartFormRawValueTests: XCTestCase {

    func testInitWithDataAndHeaders() async throws {
        // Given
        let data = "Test data".utf8

        let headers = Internals.Headers([
            ("Content-Type", "text/plain"),
            ("Content-Length", "9"),
            ("Custom-Header", "custom-value")
        ])

        // When
        let part = MultipartItem(
            name: "string",
            additionalHeaders: headers,
            data: Internals.DataBuffer(data)
        )

        let partHeaders = part.headers()

        // Then
        XCTAssertEqual(part.data.getBytes(), Array(data))
        XCTAssertEqual(partHeaders.count, 4)
        XCTAssertTrue(partHeaders.contains("form-data; name=\"string\"", for: "Content-Disposition"))
        XCTAssertTrue(partHeaders.contains("text/plain", for: "Content-Type"))
        XCTAssertTrue(partHeaders.contains("9", for: "Content-Length"))
        XCTAssertTrue(partHeaders.contains("custom-value", for: "Custom-Header"))
    }
}
