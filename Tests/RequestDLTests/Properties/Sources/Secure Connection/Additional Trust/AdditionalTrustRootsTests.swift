/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct AdditionalTrustRootsTests {

    @Test
    func additional_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let serverCertificate = try Array(Data(contentsOf: server.certificateURL))

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.AdditionalTrustRoots {
                    RequestDL.Certificate(client.certificateURL.absolutePath(percentEncoded: false))
                    RequestDL.Certificate(serverCertificate)
                }
            }
        })

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.additionalTrustRoots == .init([.certificates([
                    .init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
                    .init(serverCertificate, format: .pem)
                ])
            ])
        )
    }

    @Test
    func additional_whenFile_shouldBeValid() async throws {
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
                RequestDL.AdditionalTrustRoots(fileURL.absolutePath(percentEncoded: false))
            }
        })

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.additionalTrustRoots == .init(
                [.file(fileURL.absolutePath(percentEncoded: false))]
            )
        )
    }

    @Test
    func additional_whenBytes_shouldBeValid() async throws {
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
                RequestDL.AdditionalTrustRoots(bytes)
            }
        })

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.additionalTrustRoots == .init(
                [.bytes(bytes)]
            )
        )
    }

    @Test
    func trusts_whenAccessBody_shouldBeNever() async throws {
        // Given
        let sut = RequestDL.AdditionalTrustRoots {
            RequestDL.Certificate([0, 1, 2])
        }

        // Then
        try await assertNever(sut.body)
    }
}
