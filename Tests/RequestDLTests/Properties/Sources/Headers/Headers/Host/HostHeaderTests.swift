/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct HostHeaderTests {

    @Test
    func host() async throws {
        let property = TestProperty(HostHeader("google.com"))
        let resolved = try await resolve(property)
        #expect(resolved.request.headers["Host"] == ["google.com"])
    }

    @Test
    func hostWithPort() async throws {
        let property = TestProperty(HostHeader("google.com", port: "8080"))
        let resolved = try await resolve(property)
        #expect(resolved.request.headers["Host"] == ["google.com:8080"])
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = HostHeader("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
