/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct OriginHeaderTests {

    @Test
    func host() async throws {
        let property = TestProperty(OriginHeader("google.com"))
        let resolved = try await resolve(property)
        #expect(resolved.request.headers["Origin"] == ["google.com"])
    }

    @Test
    func hostWithPort() async throws {
        let property = TestProperty(OriginHeader("google.com", port: "8080"))
        let resolved = try await resolve(property)
        #expect(resolved.request.headers["Origin"] == ["google.com:8080"])
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = OriginHeader("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
