/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class PSKServerCertificateTests: XCTestCase {

    func testPSK_whenInit_shouldBeValid() async throws {
        // Given
        let key = SecureBytes([0, 1, 2])

        // When
        let sut = PSKServerCertificate(key).build()

        // Then
        XCTAssertEqual(sut.key, key)
    }
}
