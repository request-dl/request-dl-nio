//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct DefaultTrustRootsTests {

    @Test
    func trustRoots_whenDefault_shouldBeDefault() async throws {
        // Given
        let property = DefaultTrustRoots()

        // When
        let resolved = try await resolve(
            TestProperty {
                SecureConnection {
                    property
                }
            }
        )

        // Then
        #expect(resolved.session.configuration.secureConnection?.trustRoots == nil)
        #expect(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? false)
    }

    @Test
    func trustRoots_whenUsedWithoutEnclosingSecureConnection_shouldStillBeValid() async throws {
        // Given
        // Regression test: `DefaultTrustRoots` used to require an enclosing `SecureConnection`.
        // The base `Internals.SecureConnection` is now created lazily the first time it's needed.

        // When
        let resolved = try await resolve(
            TestProperty {
                DefaultTrustRoots()
            }
        )

        // Then
        #expect(resolved.session.configuration.secureConnection?.trustRoots == nil)
        #expect(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? false)
    }

    @Test func neverBody() async throws {
        // Given
        let property = DefaultTrustRoots()

        // Then
        try await assertNever(property.body)
    }
}
