/*
 See LICENSE for this package's licensing information.
*/

import XCTest

class CertificateTests: XCTestCase {

    func testCertificate_whenPEMBytes_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let data = try Data(contentsOf: certificates.certificateURL)

        // When
        let resolved = try Certificate(Array(data), format: .pem).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .pem))
    }

    func testCertificate_whenDERBytes_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()
        let data = try Data(contentsOf: certificates.certificateURL)

        // When
        let resolved = try Certificate(Array(data), format: .der).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .der))
    }

    func testCertificate_whenPEMFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let path = certificates.certificateURL.path

        // When
        let resolved = try Certificate(path, format: .pem).build()

        // Then
        XCTAssertEqual(resolved, try .init(file: path, format: .pem))
    }

    func testCertificate_whenDERFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()
        let path = certificates.certificateURL.path

        // When
        let resolved = try Certificate(path, format: .der).build()

        // Then
        XCTAssertEqual(resolved, try .init(file: path, format: .der))
    }
}
