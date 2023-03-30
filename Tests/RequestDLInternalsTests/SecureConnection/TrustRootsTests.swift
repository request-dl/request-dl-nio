/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDLInternals

class TrustRootsTests: XCTestCase {

    var client: CertificateResource!
    var server: CertificateResource!

    override func setUp() async throws {
        try await super.setUp()

        client = Certificates().client()
        server = Certificates().server()
    }

    func testRoots_whenDefault_shouldBeValid() async throws {
        // Given
        let root = TrustRoots.default

        // When
        let resolved = try root.build()

        // Then
        XCTAssertEqual(resolved, .default)
    }

    func testTrusts_whenCertificates_shouldBeValid() async throws {
        // Given
        var trusts = TrustRoots()
        trusts.append(.init(client.certificateURL.absolutePath()))
        trusts.append(.init(server.certificateURL.absolutePath()))

        // When
        let sut = try trusts.build()

        // Then
        XCTAssertEqual(sut, try .certificates([
            .init(file: client.certificateURL.absolutePath(), format: .pem),
            .init(file: server.certificateURL.absolutePath(), format: .pem)
        ]))
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
        let sut = try TrustRoots.file(fileURL.absolutePath()).build()

        // Then
        XCTAssertEqual(sut, .file(fileURL.absolutePath()))
    }

    func testTrustRoot_whenBytesMerged_shouldBeValid() async throws {
        // Given
        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let bytes = Array(data)

        // When
        let sut = try TrustRoots.bytes(bytes).build()

        // Then
        XCTAssertEqual(sut, try .certificates(NIOSSLCertificate.fromPEMBytes(bytes)))
    }
}
