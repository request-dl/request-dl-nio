/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class MultipartItemTests: XCTestCase {

    func testInitWithDataAndHeaders() async throws {
        // Given
        let data = "Test data".utf8

        let headers = HTTPHeaders([
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

        XCTAssertTrue(partHeaders.contains(name: "Content-Disposition") {
            $0 == "form-data; name=\"string\""
        })

        XCTAssertTrue(partHeaders.contains(name: "Content-Type") {
            $0 == "text/plain"
        })

        XCTAssertTrue(partHeaders.contains(name: "Content-Length") {
            $0 == "9"
        })

        XCTAssertTrue(partHeaders.contains(name: "Custom-Header") {
            $0 == "custom-value"
        })
    }
}
