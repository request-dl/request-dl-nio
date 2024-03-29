/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class OriginHeaderTests: XCTestCase {

    func testHost() async throws {
        let property = TestProperty(OriginHeader("google.com"))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Origin"], ["google.com"])
    }

    func testHostWithPort() async throws {
        let property = TestProperty(OriginHeader("google.com", port: "8080"))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Origin"], ["google.com:8080"])
    }

    func testNeverBody() async throws {
        // Given
        let property = OriginHeader("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
