/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class HostHeaderTests: XCTestCase {

    func testHost() async throws {
        let property = TestProperty(HostHeader("google.com"))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Host"], ["google.com"])
    }

    func testHostWithPort() async throws {
        let property = TestProperty(HostHeader("google.com", port: "8080"))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Host"], ["google.com:8080"])
    }

    func testNeverBody() async throws {
        // Given
        let property = HostHeader("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
