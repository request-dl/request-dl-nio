/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct DefaultTrustRootsTests {

    @Test
    func trusts_whenDefault_shouldBeDefault() async throws {
        // Given
        let property = DefaultTrustRoots()

        // When
        let resolved = try await resolve(TestProperty {
            SecureConnection {
                property
            }
        })

        // Then
        #expect(resolved.session.configuration.secureConnection?.trustRoots == nil)
        #expect(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? false)
    }
}
