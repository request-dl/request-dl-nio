/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
import _RequestDLExtensions
@testable import RequestDLInternals

class AdditionalTrustRootSourceTests: XCTestCase {

    func testTrustRoot_whenCertificate_shouldBeValid() async throws {
        // Given
        let seed = UUID()
        let certificate = try OpenSSL("\(seed)").certificate()
        let data = try Data(contentsOf: certificate.certificateURL)

        // When
        let certificatePEM = Certificate(Array(data), format: .pem)
        let source = AdditionalTrustRootSource.certificate(.certificate(certificatePEM))
        let resolved = try source.build()

        // Then
        XCTAssertEqual(resolved, try .certificates([certificatePEM.build()]))
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
        let source = AdditionalTrustRootSource.file(filePEM.path)
        let resolved = try source.build()

        // Then
        XCTAssertEqual(resolved, .file(filePEM.path))
    }
}