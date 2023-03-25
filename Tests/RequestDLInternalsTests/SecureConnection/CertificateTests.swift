/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import _RequestDLExtensions
@testable import RequestDLInternals

class CertificateTests: XCTestCase {

    func testCertificate_whenPEMBytes_shouldBeValid() async throws {
        // Given
        let seed = UUID()
        let certificate = try OpenSSL("\(seed)").certificate()
        let data = try Data(contentsOf: certificate.certificateURL)

        // When
        let resolved = try Certificate(Array(data), format: .pem).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .pem))
    }

    func testCertificate_whenDERBytes_shouldBeValid() async throws {
        // Given
        let seed = UUID()
        let certificate = try OpenSSL("\(seed)", with: [.der]).certificate()

        guard let url = certificate.certificateDEREncodedURL else {
            XCTFail("Missing DER URL")
            return
        }

        let data = try Data(contentsOf: url)

        // When
        let resolved = try Certificate(Array(data), format: .der).build()

        // Then
        XCTAssertEqual(resolved, try .init(bytes: Array(data), format: .der))
    }

    func testCertificate_whenPEMFile_shouldBeValid() async throws {
        // Given
        let seed = UUID()
        let certificate = try OpenSSL("\(seed)").certificate()
        let path = certificate.certificateURL.path

        // When
        let resolved = try Certificate(path, format: .pem).build()

        // Then
        XCTAssertEqual(resolved, try .init(file: path, format: .pem))
    }

    func testCertificate_whenDERFile_shouldBeValid() async throws {
        // Given
        let seed = UUID()
        let certificate = try OpenSSL("\(seed)", with: [.der]).certificate()

        guard let url = certificate.certificateDEREncodedURL else {
            XCTFail("Missing DER URL")
            return
        }

        let path = url.path

        // When
        let resolved = try Certificate(path, format: .der).build()

        // Then
        XCTAssertEqual(resolved, try .init(file: path, format: .der))
    }
}
