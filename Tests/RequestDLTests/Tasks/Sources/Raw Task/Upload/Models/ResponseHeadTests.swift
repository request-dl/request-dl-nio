/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

// swiftlint:disable file_length type_body_length
class ResponseHeadTests: XCTestCase {

    func testHead_whenDebugDescription() {
        // Given
        let headers = HTTPHeaders([
            ("Content-Type", "application/json"),
            ("Accept", "application/json"),
            ("Accept", "text/plain"),
            ("Accept", "text/html"),
            ("Accept-Language", "en-US")
        ])

        let responseHead = ResponseHead(
            url: URL(string: "https://google.com/?q=search"),
            status: .init(code: 200, reason: "Ok"),
            version: .init(minor: 1, major: 3),
            headers: headers,
            isKeepAlive: false
        )

        // Then
        XCTAssertEqual(responseHead.debugDescription, """
            https://google.com/?q=search
            200 Ok Status

            HTTP version range: 1 ... 3
            Keep alive: false

            Content-Type: application/json
            Accept: application/json
            Accept: text/plain
            Accept: text/html
            Accept-Language: en-US
            """
        )
    }
}
