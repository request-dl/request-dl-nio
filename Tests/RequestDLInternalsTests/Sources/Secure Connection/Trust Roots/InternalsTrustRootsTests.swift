//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

struct InternalsTrustRootsTests {

    @Test
    func trustRoots_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        var trustRoots = Internals.TrustRoots()
        trustRoots.append(.init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem))
        trustRoots.append(.init(server.certificateURL.absolutePath(percentEncoded: false), format: .pem))

        // When
        let sut = try trustRoots.build()

        // Then
        let expectedTrustRoots = try NIOSSLTrustRoots.certificates(
            NIOSSLCertificate.fromPEMFile(client.certificateURL.absolutePath(percentEncoded: false))
                + NIOSSLCertificate.fromPEMFile(server.certificateURL.absolutePath(percentEncoded: false))
        )
        #expect(sut == expectedTrustRoots)
    }

    @Test
    func trustRoot_whenFilesMerged_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let fileURL =
            temporaryDirectoryURL
            .appendingPathComponent("RequestDL.\(UUID())")
            .appendingPathComponent("merged.pem")

        defer { fileURL.scheduleRemoval() }
        try await fileURL.createPathIfNeeded()

        try data.write(to: fileURL)

        // When
        let sut = try Internals.TrustRoots.file(fileURL.absolutePath(percentEncoded: false)).build()

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
        let sut = try Internals.TrustRoots.bytes(bytes).build()

        // Then
        let expectedTrustRoots = try NIOSSLTrustRoots.certificates(NIOSSLCertificate.fromPEMBytes(bytes))
        #expect(sut == expectedTrustRoots)
    }
}
