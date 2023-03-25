/*
 See LICENSE for this package's licensing information.
*/

#if os(macOS) || os(Linux)
import XCTest
import NIOSSL
import _RequestDLExtensions
@testable import RequestDLInternals

class ChainCertificateTests: XCTestCase {

    func testChain_whenMultipleCertificates_shouldBeValid() async throws {
        // Given
        let seeds = [UUID(), UUID(), UUID()]
        let openSSL = try seeds.map {
            try OpenSSL("\($0)").certificate()
        }
        let contents = try openSSL.map {
            try Data(contentsOf: $0.certificateURL)
        }

        let filePEM = openSSL[0].certificateURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(UUID()).merged.pem")

        if !FileManager.default.fileExists(atPath: filePEM.path) {
            FileManager.default.createFile(atPath: filePEM.path, contents: nil)
        }

        try Data(contents[1...2].joined()).write(to: filePEM)

        // When
        let certificate = Certificate(Array(contents[0]), format: .pem)
        let source = ChainCertificate([
            .certificate(certificate),
            .file(filePEM.path)
        ])
        let resolved = try source.build()

        // Then
        XCTAssertEqual(resolved, try [
            .certificate(certificate.build()),
        ] + CertificateSource.file(filePEM.path).build().map {
            .certificate($0)
        })
    }
}
#endif
