//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

// Every test here goes through `Internals.AdditionalTrustRoots.build()`, which only exists under
// `canImport(NIOCore)` (it returns `NIOSSLAdditionalTrustRoots`); the portable counterpart,
// `resolvedDERBytes()`, has no test of its own yet.
#if canImport(NIOCore)
import NIOSSL

struct InternalsAdditionalTrustRootsTests {

    @Test
    func trustRoots_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        var trustRoots = Internals.AdditionalTrustRoots()
        trustRoots.append(.init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem))
        trustRoots.append(.init(server.certificateURL.absolutePath(percentEncoded: false), format: .pem))

        // When
        let sut = try trustRoots.build()

        // Then
        let expectedAdditionalTrustRoots = try NIOSSLAdditionalTrustRoots.certificates(
            NIOSSLCertificate.fromPEMFile(client.certificateURL.absolutePath(percentEncoded: false))
                + NIOSSLCertificate.fromPEMFile(server.certificateURL.absolutePath(percentEncoded: false))
        )
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

        try await withTemporaryFileURL("merged.pem") { fileURL in
            try data.write(to: fileURL)

            // When
            let sut = try Internals.AdditionalTrustRoots.file(fileURL.absolutePath(percentEncoded: false)).build()

            // Then
            #expect(sut == .file(fileURL.absolutePath(percentEncoded: false)))
        }
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

#endif
