/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOSSL
@testable import RequestDL

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
