//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

// `Internals.Certificate.Format.build()` only exists under `canImport(NIOCore)` (it returns
// `NIOSSLSerializationFormats`); `.pathExtension` is the only portable member, and it has no
// test of its own yet.
#if canImport(NIOCore)
import NIOSSL

struct InternalsCertificateFormatTests {

    @Test
    func format_whenIsPEM_shouldBePEM() async throws {
        // Given
        let format = Internals.Certificate.Format.pem

        // When
        let resolved = format.build()

        // Then
        #expect(resolved == .pem)
    }

    @Test
    func format_whenIsDER_shouldBeDER() async throws {
        // Given
        let format = Internals.Certificate.Format.der

        // When
        let resolved = format.build()

        // Then
        #expect(resolved == .der)
    }
}

#endif
