/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDLInternals

class CertificateSourceTests: XCTestCase {

    func testSource_whenCertificate_shouldBeValid() async throws {
        // Given
        let openSSL = Certificates().client()
        let data = try Data(contentsOf: openSSL.certificateURL)

        // When
        let certificatePEM = Certificate(Array(data), format: .pem)
        let source = CertificateSource.certificate(certificatePEM)
        let resolved = try source.build()

        // Then
        XCTAssertEqual(resolved, try [certificatePEM.build()])
    }

    func testSource_whenBytes_shouldBeValid() async throws {
        // Given
        let certificates = [
            Certificates().client(),
            Certificates().server()
        ]

        let data = try certificates.map {
            try Data(contentsOf: $0.certificateURL)
        }.joined()

        // When
        let source = CertificateSource.bytes(Array(data))
        let resolved = try source.build()

        // Then
        XCTAssertEqual(resolved, try NIOSSLCertificate.fromPEMBytes(Array(data)))
    }

    func testSource_whenFile_shouldBeValid() async throws {
        // Given
        let certificates = [
            Certificates().client(),
            Certificates().server()
        ]

        let data = try certificates.map {
            try Data(contentsOf: $0.certificateURL)
        }.joined()

        let filePEM = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestDL.\(UUID())")
            .appendingPathComponent("merged.pem")

        try filePEM.createPathIfNeeded()
        try Data(data).write(to: filePEM)

        // When
        let source = CertificateSource.file(filePEM.path)
        let resolved = try source.build()

        // Then
        XCTAssertEqual(resolved, try NIOSSLCertificate.fromPEMFile(filePEM.path))
    }
}
