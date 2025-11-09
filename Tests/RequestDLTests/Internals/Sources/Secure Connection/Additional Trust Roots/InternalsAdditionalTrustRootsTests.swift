/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOSSL
@testable import RequestDL

struct InternalsAdditionalTrustRootsTests {

    @Test
    func trusts_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        var trusts = Internals.AdditionalTrustRoots()
        trusts.append(.init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem))
        trusts.append(.init(server.certificateURL.absolutePath(percentEncoded: false), format: .pem))

        // When
        let sut = try trusts.build()

        // Then
        let expectedAdditionalTrustRoots = try NIOSSLAdditionalTrustRoots.certificates([
            .init(file: client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
            .init(file: server.certificateURL.absolutePath(percentEncoded: false), format: .pem)
        ])
        #expect(sut == expectedAdditionalTrustRoots)
    }

    @Test
    func trustRoot_whenFilesMerged_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

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
        let sut = try Internals.AdditionalTrustRoots.file(fileURL.absolutePath(percentEncoded: false)).build()

        // Then
        #expect(sut == .file(fileURL.absolutePath(percentEncoded: false)))
    }

    @Test
    func trustRoot_whenBytesMerged_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let bytes = Array(data)

        // When
        let sut = try Internals.AdditionalTrustRoots.bytes(bytes).build()

        // Then
        let expectedAdditionalTrustRoots = try NIOSSLAdditionalTrustRoots.certificates(
            NIOSSLCertificate.fromPEMBytes(bytes)
        )
        #expect(sut == expectedAdditionalTrustRoots)
    }
}
