/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

class InternalsCertificateChainTests: XCTestCase {

    var client: CertificateResource?
    var server: CertificateResource?

    override func setUp() async throws {
        try await super.setUp()

        client = Certificates().client()
        server = Certificates().server()
    }

    func testChain_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = try XCTUnwrap(server)
        let client = try XCTUnwrap(client)

        var chain = Internals.CertificateChain()

        chain.append(
            Internals.Certificate(
                client.certificateURL.absolutePath(percentEncoded: false),
                format: .pem
            )
        )

        chain.append(
            Internals.Certificate(
                server.certificateURL.absolutePath(percentEncoded: false),
                format: .pem
            )
        )

        // When
        let sut = try chain.build()

        // Then
        XCTAssertEqual(sut, try [
            .certificate(.init(file: client.certificateURL.absolutePath(percentEncoded: false), format: .pem)),
            .certificate(.init(file: server.certificateURL.absolutePath(percentEncoded: false), format: .pem))
        ])
    }

    func testTrustRoot_whenFilesMerged_shouldBeValid() async throws {
        // Given
        let server = try XCTUnwrap(server)
        let client = try XCTUnwrap(client)

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
        let sut = try Internals.CertificateChain.file(fileURL.absolutePath(percentEncoded: false)).build()

        // Then
        XCTAssertEqual(sut, try NIOSSLCertificate.fromPEMFile(fileURL.absolutePath(percentEncoded: false)).map {
            .certificate($0)
        })
    }

    func testTrustRoot_whenBytesMerged_shouldBeValid() async throws {
        // Given
        let server = try XCTUnwrap(server)
        let client = try XCTUnwrap(client)

        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let bytes = Array(data)

        // When
        let sut = try Internals.CertificateChain.bytes(bytes).build()

        // Then
        XCTAssertEqual(sut, try NIOSSLCertificate.fromPEMBytes(bytes).map {
            .certificate($0)
        })
    }
}
