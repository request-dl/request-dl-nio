//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

struct ResponseHeadTests {

    @Test
    func head_whenDebugDescription() {
        // Given
        let headers = HTTPHeaders([
            ("Content-Type", "application/json"),
            ("Accept", "application/json"),
            ("Accept", "text/plain"),
            ("Accept", "text/html"),
            ("Accept-Language", "en-US"),
        ])

        let responseHead = ResponseHead(
            url: URL(string: "https://google.com/?q=search"),
            status: .init(code: 200, reason: "Ok"),
            version: .init(minor: 1, major: 3),
            headers: headers,
            isKeepAlive: false
        )

        // Then
        #expect(
            responseHead.debugDescription == """
                https://google.com/?q=search
                200 Ok Status

                HTTP/3.1
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
