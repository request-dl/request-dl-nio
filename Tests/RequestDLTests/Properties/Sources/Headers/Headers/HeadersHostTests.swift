/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersHostTests: XCTestCase {

    func testHost() async throws {
        let property = TestProperty(Headers.Host("google.com"))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Host"), "google.com")
    }

    func testHostWithPort() async throws {
        let property = TestProperty(Headers.Host("google.com", port: "8080"))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Host"), "google.com:8080")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Host("apple.com")

        // Then
        try await assertNever(property.body)
    }
}