/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsResponseHeadTests {

    @Test
    func response_whenHeadInit_shouldBeValid() async throws {
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
        #expect(responseHead.url == url)
        #expect(responseHead.status.code == 200)
        #expect(responseHead.status.reason == "OK")
        #expect(responseHead.version.minor == 0)
        #expect(responseHead.version.major == 1)
        #expect(responseHead.headers == headers)
        #expect(responseHead.isKeepAlive)
    }

    @Test
    func response_whenStatusInit_shouldBeValid() async throws {
        // Given
        let status = Internals.ResponseHead.Status(code: 200, reason: "OK")

        // Then
        #expect(status.code == 200)
        #expect(status.reason == "OK")
    }

    @Test
    func response_whenVersionInit_shouldBeValid() async throws {
        // Given
        let version = Internals.ResponseHead.Version(minor: 0, major: 1)

        // Then
        #expect(version.minor == 0)
        #expect(version.major == 1)
    }
}
