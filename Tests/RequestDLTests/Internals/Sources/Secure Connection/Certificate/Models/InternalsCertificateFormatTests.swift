/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

@RequestActor
class InternalsCertificateFormatTests: XCTestCase {

    func testFormat_whenIsPEM_shouldBePEM() async throws {
        // Given
        let format = Internals.Certificate.Format.pem

        // When
        let resolved = format.build()

        // Then
        XCTAssertEqual(resolved, .pem)
    }

    func testFormat_whenIsDER_shouldBeDER() async throws {
        // Given
        let format = Internals.Certificate.Format.der

        // When
        let resolved = format.build()

        // Then
        XCTAssertEqual(resolved, .der)
    }
}
