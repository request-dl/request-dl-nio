/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
import _RequestDLServer
import _RequestDLExtensions
@testable import RequestDLInternals

class ChainCertificateTests: XCTestCase {

    func testChain_whenMultipleCertificates_shouldBeValid() async throws {
        // Given
        let certificates = [
            Certificates().client(),
            Certificates().server()
        ]

        let contents = try certificates.map {
            try Data(contentsOf: $0.certificateURL)
        }

        let filePEM = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestDL.\(UUID())")
            .appendingPathComponent("merged.pem")

        try filePEM.createPathIfNeeded()
        try Data(contents.joined()).write(to: filePEM)

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
