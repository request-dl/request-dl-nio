/*
 See LICENSE for this package's licensing information.
*/

#if os(macOS) || os(Linux)
import XCTest
import NIOSSL
import _RequestDLExtensions
@testable import RequestDLInternals

class CertificateSourceTests: XCTestCase {

    func testSource_whenCertificate_shouldBeValid() async throws {
        // Given
        let openSSL = try OpenSSL().certificate()
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
        let seeds = [UUID(), UUID(), UUID()]
        let openSSL = try seeds.map {
            try OpenSSL("\($0)").certificate()
        }
        let data = try openSSL.map {
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
        let seeds = [UUID(), UUID(), UUID()]
        let openSSL = try seeds.map {
            try OpenSSL("\($0)").certificate()
        }
        let data = try openSSL.map {
            try Data(contentsOf: $0.certificateURL)
        }.joined()

        let filePEM = openSSL[0].certificateURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(UUID()).merged.pem")

        if !FileManager.default.fileExists(atPath: filePEM.path) {
            FileManager.default.createFile(atPath: filePEM.path, contents: nil)
        }

        try Data(data).write(to: filePEM)

        // When
        let source = CertificateSource.file(filePEM.path)
        let resolved = try source.build()

        // Then
        XCTAssertEqual(resolved, try NIOSSLCertificate.fromPEMFile(filePEM.path))
    }
}
#endif
