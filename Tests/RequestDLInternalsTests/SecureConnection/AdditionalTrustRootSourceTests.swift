/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDLInternals

class AdditionalTrustRootSourceTests: XCTestCase {

    func testTrustRoot_whenCertificate_shouldBeValid() async throws {
        // Given
        let openSSL = Certificates().client()
        let data = try Data(contentsOf: openSSL.certificateURL)

        // When
        let certificatePEM = Certificate(Array(data), format: .pem)
        let source = AdditionalTrustRootSource.certificate(.certificate(certificatePEM))
        let resolved = try source.build()

        // Then
        XCTAssertEqual(resolved, try .certificates([certificatePEM.build()]))
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
        let source = AdditionalTrustRootSource.file(filePEM.path)
        let resolved = try source.build()

        // Then
        XCTAssertEqual(resolved, .file(filePEM.path))
    }
}
