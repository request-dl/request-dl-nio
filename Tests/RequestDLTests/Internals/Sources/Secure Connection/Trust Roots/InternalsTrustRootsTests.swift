/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOSSL
@testable import RequestDL

struct InternalsTrustRootsTests {

    var client: CertificateResource?
    var server: CertificateResource?

    override func setUp() async throws {
        try await super.setUp()

        client = Certificates().client()
        server = Certificates().server()
    }

    @Test
    func trusts_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = try #require(server)
        let client = try #require(client)

        var trusts = Internals.TrustRoots()
        trusts.append(.init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem))
        trusts.append(.init(server.certificateURL.absolutePath(percentEncoded: false), format: .pem))

        // When
        let sut = try trusts.build()

        // Then
        #expect(sut == try .certificates([
            .init(file: client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
            .init(file: server.certificateURL.absolutePath(percentEncoded: false), format: .pem)
        ]))
    }

    @Test
    func trustRoot_whenFilesMerged_shouldBeValid() async throws {
        // Given
        let server = try #require(server)
        let client = try #require(client)

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
        let sut = try Internals.TrustRoots.file(fileURL.absolutePath(percentEncoded: false)).build()

        // Then
        #expect(sut == .file(fileURL.absolutePath(percentEncoded: false)))
    }

    @Test
    func trustRoot_whenBytesMerged_shouldBeValid() async throws {
        // Given
        let server = try #require(server)
        let client = try #require(client)

        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let bytes = Array(data)

        // When
        let sut = try Internals.TrustRoots.bytes(bytes).build()

        // Then
        #expect(sut == try .certificates(NIOSSLCertificate.fromPEMBytes(bytes)))
    }
}
