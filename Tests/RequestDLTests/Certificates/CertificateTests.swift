/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class CertificateTests: XCTestCase {

    func testCertificateInitialization() {
        // Given
        let name = "myCertificate"
        let bundle = Bundle(for: CertificateTests.self)

        // When
        let certificate = Certificate(name, in: bundle)

        // Then
        XCTAssertEqual(certificate.name, name)
        XCTAssertEqual(certificate.bundle, bundle)
    }
}