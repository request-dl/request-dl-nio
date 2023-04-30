/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class HeadersOriginTests: XCTestCase {

    func testHost() async throws {
        let property = TestProperty(Headers.Origin("google.com"))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Origin"), "google.com")
    }

    func testHostWithPort() async throws {
        let property = TestProperty(Headers.Origin("google.com", port: "8080"))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Origin"), "google.com:8080")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Origin("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
