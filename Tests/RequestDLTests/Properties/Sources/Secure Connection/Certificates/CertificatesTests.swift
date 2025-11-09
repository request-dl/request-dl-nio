/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct CertificatesTests {

    @Test
    func certificates_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let serverCertificate = try Array(Data(contentsOf: server.certificateURL))

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Certificates {
                    RequestDL.Certificate(client.certificateURL.absolutePath(percentEncoded: false))
                    RequestDL.Certificate(serverCertificate)
                    RequestDL.Certificate("client.public", in: .module)
                }
            }
        })

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.certificateChain == .certificates([
                .init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
                .init(serverCertificate, format: .pem),
                .init(
                    Bundle.module
                        .url(forResource: "client.public", withExtension: "pem")?
                        .absolutePath(percentEncoded: false) ?? "",
                    format: .pem
                )
            ])
        )
    }

    @Test
    func certificates_whenFile_shouldBeValid() async throws {
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
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Certificates(fileURL.absolutePath(percentEncoded: false))
            }
        })

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.certificateChain == .file(
                fileURL.absolutePath(percentEncoded: false)
            )
        )
    }

    @Test
    func certificates_whenBytes_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let bytes = Array(data)

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Certificates(bytes)
            }
        })

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.certificateChain == .bytes(bytes)
        )
    }

    @Test
    func certificates_whenAccessBody_shouldBeNever() async throws {
        // Given
        let sut = RequestDL.Certificates {
            RequestDL.Certificate([0, 1, 2])
        }

        // Then
        try await assertNever(sut.body)
    }
}
