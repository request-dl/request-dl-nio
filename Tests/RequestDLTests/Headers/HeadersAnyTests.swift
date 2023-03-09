/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersAnyTests: XCTestCase {

    func testSingleHeaderAny() async {
        let property = TestProperty(Headers.Any("password", forKey: "xxx-api-key"))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password")
    }

    func testHeadersAny() async {
        let property = TestProperty {
            Headers.Any("text/html", forKey: "Accept")
            Headers.Any("gzip", forKey: "Content-Encoding")
        }

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/html")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Encoding"), "gzip")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Any(123, forKey: "key")

        // Then
        try await assertNever(property.body)
    }
}
