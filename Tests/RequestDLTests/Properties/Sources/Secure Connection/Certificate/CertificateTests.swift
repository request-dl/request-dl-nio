//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct CertificateTests {

    @Test func neverBody() async throws {
        // Given
        let property = Certificate([0, 1, 2])

        // Then
        try await assertNever(property.body)
    }
}
