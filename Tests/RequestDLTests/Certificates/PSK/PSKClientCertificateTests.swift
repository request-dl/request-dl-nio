/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class PSKClientCertificateTests: XCTestCase {

    func testPSK_whenInit_shouldBeValid() async throws {
        // Given
        let identity = "host"
        let key = SecureBytes([0, 1, 2])

        // When
        let sut = PSKClientCertificate(
            key: key,
            identity: identity
        ).build()

        // Then
        XCTAssertEqual(sut.identity, identity)
        XCTAssertEqual(sut.key, key)
    }
}
