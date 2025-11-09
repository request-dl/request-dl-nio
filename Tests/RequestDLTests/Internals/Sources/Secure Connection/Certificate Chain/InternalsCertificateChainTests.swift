/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOSSL
@testable import RequestDL

struct InternalsCertificateChainTests {

    @Test
    func chain_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

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
        let expectedSources: [NIOSSLCertificateSource] = try [
            .certificate(.init(file: client.certificateURL.absolutePath(percentEncoded: false), format: .pem)),
            .certificate(.init(file: server.certificateURL.absolutePath(percentEncoded: false), format: .pem))
        ]
        #expect(sut == expectedSources)
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
        let sut = try Internals.CertificateChain.file(fileURL.absolutePath(percentEncoded: false)).build()

        // Then
        let expectedSources = try NIOSSLCertificate.fromPEMFile(fileURL.absolutePath(percentEncoded: false)).map {
            NIOSSLCertificateSource.certificate($0)
        }
        #expect(sut == expectedSources)
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
        let sut = try Internals.CertificateChain.bytes(bytes).build()

        // Then
        let expectedSources = try NIOSSLCertificate.fromPEMBytes(bytes).map {
            NIOSSLCertificateSource.certificate($0)
        }
        #expect(sut == expectedSources)
    }
}
