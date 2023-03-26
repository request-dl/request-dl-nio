/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDLInternals

class TrustRootsTests: XCTestCase {

    func testRoots_whenDefault_shouldBeValid() async throws {
        // Given
        let root = TrustRoots.default

        // When
        let resolved = try root.build()

        // Then
        XCTAssertEqual(resolved, .default)
    }

    func testRoots_whenCertificate_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let data = try Data(contentsOf: certificates.certificateURL)

        // When
        let resolved = try TrustRoots.certificate(.bytes(Array(data))).build()

        // Then
        XCTAssertEqual(resolved, try .certificates(NIOSSLCertificate.fromPEMBytes(Array(data))))
    }

    func testRoots_whenFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()

        // When
        let resolved = try TrustRoots.file(certificates.certificateURL.path).build()

        // Then
        XCTAssertEqual(resolved, .file(certificates.certificateURL.path))
    }
}
