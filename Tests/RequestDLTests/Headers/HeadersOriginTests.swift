/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersOriginTests: XCTestCase {

    func testHost() async throws {
        let property = TestProperty(Headers.Origin("google.com"))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "google.com")
    }

    func testHostWithPort() async throws {
        let property = TestProperty(Headers.Origin("google.com", port: "8080"))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "google.com:8080")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Origin("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
