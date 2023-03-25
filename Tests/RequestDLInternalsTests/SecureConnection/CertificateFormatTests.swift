/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDLInternals

class CertificateFormatTests: XCTestCase {

    func testFormat_whenIsPEM_shouldBePEM() async throws {
        // Given
        let format = CertificateFormat.pem

        // When
        let resolved = format.build()

        // Then
        XCTAssertEqual(resolved, .pem)
    }

    func testFormat_whenIsDER_shouldBeDER() async throws {
        // Given
        let format = CertificateFormat.der

        // When
        let resolved = format.build()

        // Then
        XCTAssertEqual(resolved, .der)
    }
}
