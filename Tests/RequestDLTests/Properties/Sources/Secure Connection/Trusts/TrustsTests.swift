/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct TrustsTests {

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
        let server = try Array(Data(contentsOf: #require(server).certificateURL))
        let client = try #require(client)

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Trusts {
                    RequestDL.Certificate(client.certificateURL.absolutePath(percentEncoded: false))
                    RequestDL.Certificate(server)
                }
            }
        })

        // Then
        #expect(!resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true)
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots,
            .certificates([
                .init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
                .init(server, format: .pem)
            ])
        )
    }

    @Test
    func trusts_whenFile_shouldBeValid() async throws {
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
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Trusts(fileURL.absolutePath(percentEncoded: false))
            }
        })

        // Then
        #expect(!resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true)
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots,
            .file(fileURL.absolutePath(percentEncoded: false))
        )
    }

    @Test
    func trusts_whenBytes_shouldBeValid() async throws {
        // Given
        let server = try #require(server)
        let client = try #require(client)

        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let bytes = Array(data)

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Trusts(bytes)
            }
        })

        // Then
        #expect(!resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true)
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots,
            .bytes(bytes)
        )
    }

    @Test
    func trusts_whenAccessBody_shouldBeNever() async throws {
        // Given
        let sut = RequestDL.Trusts {
            RequestDL.Certificate([0, 1, 2])
        }

        // Then
        try await assertNever(sut.body)
    }
}
