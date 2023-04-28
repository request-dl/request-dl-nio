/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class HeadersAnyTests: XCTestCase {

    func testSingleHeaderAny() async throws {
        let property = TestProperty(Headers.Any("password", forKey: "xxx-api-key"))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "xxx-api-key"), "password")
    }

    func testHeadersAny() async throws {
        let property = TestProperty {
            Headers.Any("text/html", forKey: "Accept")
            Headers.Any("gzip", forKey: "Content-Encoding")
        }

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "text/html")
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Encoding"), "gzip")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Any(123, forKey: "key")

        // Then
        try await assertNever(property.body)
    }
}
