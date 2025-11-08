/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct DNSOverrideTests {

    @Test
    func dnsOverride() async throws {
        // Given
        let destination = UUID().uuidString
        let origin = UUID().uuidString

        // When
        let resolved = try await resolve(
            DNSOverride(destination, from: origin)
        )

        // Then
        #expect(resolved.session.configuration.dnsOverride == [
            origin: destination
        ])
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = DNSOverride("localhost", from: "google.com")

        // Then
        try await assertNever(property.body)
    }
}
