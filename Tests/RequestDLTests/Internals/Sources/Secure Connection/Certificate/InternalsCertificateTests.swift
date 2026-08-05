//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsCertificateTests {

    @Test
    func certificate_whenPEMBytes_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let data = try Data(contentsOf: certificates.certificateURL)

        // When
        let resolved = try Internals.Certificate(Array(data), format: .pem).build()

        // Then
        let expectedCertificates: [NIOSSLCertificate] = try [
            .init(bytes: Array(data), format: .pem)
        ]
        #expect(resolved == expectedCertificates)
    }

    @Test
    func certificate_whenDERBytes_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()
        let data = try Data(contentsOf: certificates.certificateURL)

        // When
        let resolved = try Internals.Certificate(Array(data), format: .der).build()

        // Then
        let expectedCertificates: [NIOSSLCertificate] = try [
            .init(bytes: Array(data), format: .der)
        ]
        #expect(resolved == expectedCertificates)
    }

    @Test
    func certificate_whenPEMFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let path = certificates.certificateURL.path

        // When
        let resolved = try Internals.Certificate(path, format: .pem).build()

        // Then
        let expectedCertificates = try NIOSSLCertificate.fromPEMFile(path)
        #expect(resolved == expectedCertificates)
    }

    @Test
    func certificate_whenDERFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()
        let path = certificates.certificateURL.path

        // When
        let resolved = try Internals.Certificate(path, format: .der).build()

        // Then
        let expectedCertificates = try [NIOSSLCertificate.fromDERFile(path)]
        #expect(resolved == expectedCertificates)
    }
}
