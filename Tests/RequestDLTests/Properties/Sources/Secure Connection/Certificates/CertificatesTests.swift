//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
// import struct Foundation.UUID
#endif

#if canImport(Darwin)
// import class Foundation.Bundle
#endif

struct CertificatesTests {

    @Test
    func certificates_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let serverCertificate = try Array(Data(contentsOf: server.certificateURL))

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.Certificates {
                        RequestDL.Certificate(client.certificateURL.absolutePath(percentEncoded: false))
                        RequestDL.Certificate(serverCertificate)
                        // `Certificate(_:in:format:)` only exists on Darwin — it is built on
                        // `Bundle`, which is not part of `FoundationEssentials`.
                        #if canImport(Darwin)
                        RequestDL.Certificate("client.public", in: .module)
                        #endif
                    }
                }
            }
        )

        // Then
        // Built outside the `#expect` macro: `#if` inside a macro argument does not parse
        // reliably, since the macro needs a single well formed expression before conditional
        // compilation is resolved.
        var expectedCertificates: [Internals.Certificate] = [
            .init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
            .init(serverCertificate, format: .pem),
        ]

        #if canImport(Darwin)
        expectedCertificates.append(
            .init(
                Bundle.module
                    .url(forResource: "client.public", withExtension: "pem")?
                    .absolutePath(percentEncoded: false) ?? "",
                format: .pem
            )
        )
        #endif

        #expect(
            resolved.session.configuration.secureConnection?.certificateChain
                == .certificates(expectedCertificates)
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

        let fileURL =
            temporaryDirectoryURL
            .appendingPathComponent("RequestDL.\(UUID())")
            .appendingPathComponent("merged.pem")

        defer { fileURL.scheduleRemoval() }
        try await fileURL.createPathIfNeeded()

        try data.write(to: fileURL)

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.Certificates(fileURL.absolutePath(percentEncoded: false))
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.certificateChain
                == .file(
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
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.Certificates(bytes)
                }
            }
        )

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
