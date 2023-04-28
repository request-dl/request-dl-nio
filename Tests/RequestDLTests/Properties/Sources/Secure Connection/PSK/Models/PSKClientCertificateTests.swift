/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

@RequestActor
class PSKClientCertificateTests: XCTestCase {

    func testPSK_whenInit_shouldBeValid() async throws {
        // Given
        let identity = "host"
        let key = NIOSSLSecureBytes([0, 1, 2])

        // When
        let sut = PSKClientIdentity(
            key: key,
            identity: identity
        ).build()

        // Then
        XCTAssertEqual(sut.identity, identity)
        XCTAssertEqual(sut.key, key)
    }
}
