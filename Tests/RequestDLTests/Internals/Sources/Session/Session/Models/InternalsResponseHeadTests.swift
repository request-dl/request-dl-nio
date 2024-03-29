/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InternalsResponseHeadTests: XCTestCase {

    func testResponse_whenHeadInit_shouldBeValid() async throws {
        // Given
        let url = "https://127.0.0.1"
        let status = Internals.ResponseHead.Status(code: 200, reason: "OK")
        let version = Internals.ResponseHead.Version(minor: 0, major: 1)
        var headers = HTTPHeaders()
        let isKeepAlive = true

        headers.set(name: "Content-Type", value: "text/html")

        // When
        let responseHead = Internals.ResponseHead(
            url: url,
            status: status,
            version: version,
            headers: headers,
            isKeepAlive: isKeepAlive
        )

        // Then
        XCTAssertEqual(responseHead.url, url)
        XCTAssertEqual(responseHead.status.code, 200)
        XCTAssertEqual(responseHead.status.reason, "OK")
        XCTAssertEqual(responseHead.version.minor, 0)
        XCTAssertEqual(responseHead.version.major, 1)
        XCTAssertEqual(responseHead.headers, headers)
        XCTAssertTrue(responseHead.isKeepAlive)
    }

    func testResponse_whenStatusInit_shouldBeValid() async throws {
        // Given
        let status = Internals.ResponseHead.Status(code: 200, reason: "OK")

        // Then
        XCTAssertEqual(status.code, 200)
        XCTAssertEqual(status.reason, "OK")
    }

    func testResponse_whenVersionInit_shouldBeValid() async throws {
        // Given
        let version = Internals.ResponseHead.Version(minor: 0, major: 1)

        // Then
        XCTAssertEqual(version.minor, 0)
        XCTAssertEqual(version.major, 1)
    }
}
