/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct TrustRootsTests {

    @Test
    func trusts_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let serverCertificate = try Array(Data(contentsOf: server.certificateURL))

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.TrustRoots {
                    RequestDL.Certificate(client.certificateURL.absolutePath(percentEncoded: false))
                    RequestDL.Certificate(serverCertificate)
                }
            }
        })

        // Then
        #expect(!(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true))
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots == .certificates([
                .init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
                .init(serverCertificate, format: .pem)
            ])
        )
    }

    @Test
    func trusts_whenFile_shouldBeValid() async throws {
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
                RequestDL.TrustRoots(fileURL.absolutePath(percentEncoded: false))
            }
        })

        // Then
        #expect(!(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true))
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots == .file(
                fileURL.absolutePath(percentEncoded: false)
            )
        )
    }

    @Test
    func trusts_whenBytes_shouldBeValid() async throws {
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
                RequestDL.TrustRoots(bytes)
            }
        })

        // Then
        #expect(!(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true))
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots == .bytes(bytes)
        )
    }

    @Test
    func trusts_whenAccessBody_shouldBeNever() async throws {
        // Given
        let sut = RequestDL.TrustRoots {
            RequestDL.Certificate([0, 1, 2])
        }

        // Then
        try await assertNever(sut.body)
    }
}
