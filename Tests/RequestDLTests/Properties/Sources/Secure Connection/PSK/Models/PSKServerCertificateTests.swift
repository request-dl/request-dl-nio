/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

@available(*, deprecated)
@RequestActor
class PSKServerCertificateTests: XCTestCase {

    func testPSK_whenInit_shouldBeValid() async throws {
        // Given
        let key = NIOSSLSecureBytes([0, 1, 2])

        // When
        let sut = PSKServerIdentity(key).build()

        // Then
        XCTAssertEqual(sut.key, key)
    }
}
