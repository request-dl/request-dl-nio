/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDLInternals

class CertificateChainTests: XCTestCase {

    var client: CertificateResource!
    var server: CertificateResource!

    override func setUp() async throws {
        try await super.setUp()

        client = Certificates().client()
        server = Certificates().server()
    }

    func testChain_whenCertificates_shouldBeValid() async throws {
        // Given
        var chain = CertificateChain()
        chain.append(.init(client.certificateURL.absolutePath()))
        chain.append(.init(server.certificateURL.absolutePath()))

        // When
        let sut = try chain.build()

        // Then
        XCTAssertEqual(sut, try [
            .certificate(.init(file: client.certificateURL.absolutePath(), format: .pem)),
            .certificate(.init(file: server.certificateURL.absolutePath(), format: .pem))
        ])
    }

    func testTrustRoot_whenFilesMerged_shouldBeValid() async throws {
        // Given
        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestDL.\(UUID())")
            .appendingPathComponent("merged.pem")

        defer { try? fileURL.removeIfNeeded() }
        try fileURL.createPathIfNeeded()

        try data.write(to: fileURL)

        // When
        let sut = try CertificateChain.file(fileURL.absolutePath()).build()

        // Then
        XCTAssertEqual(sut, try NIOSSLCertificate.fromPEMFile(fileURL.absolutePath()).map {
            .certificate($0)
        })
    }

    func testTrustRoot_whenBytesMerged_shouldBeValid() async throws {
        // Given
        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let bytes = Array(data)

        // When
        let sut = try CertificateChain.bytes(bytes).build()

        // Then
        XCTAssertEqual(sut, try NIOSSLCertificate.fromPEMBytes(bytes).map {
            .certificate($0)
        })
    }
}