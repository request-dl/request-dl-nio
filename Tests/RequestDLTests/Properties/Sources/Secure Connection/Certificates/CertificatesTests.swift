/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

#if !canImport(Network)
class CertificatesTests: XCTestCase {

    var client: CertificateResource?
    var server: CertificateResource?

    override func setUp() async throws {
        try await super.setUp()
        client = Certificates().client()
        server = Certificates().server()
    }

    func testCertificates_whenCertificates_shouldBeValid() async throws {
        // Given
        let client = try XCTUnwrap(client)

        let server = try Array(Data(contentsOf: XCTUnwrap(server).certificateURL))

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Certificates {
                    RequestDL.Certificate(client.certificateURL.absolutePath(percentEncoded: false))
                    RequestDL.Certificate(server)
                    RequestDL.Certificate("client.public", in: .module)
                }
            }
        })

        // Then
        XCTAssertEqual(
            resolved.session.configuration.secureConnection?.certificateChain,
            .certificates([
                .init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
                .init(server, format: .pem),
                .init(
                    Bundle.module
                        .url(forResource: "client.public", withExtension: "pem")?
                        .absolutePath(percentEncoded: false) ?? "",
                    format: .pem
                )
            ])
        )
    }

    func testCertificates_whenFile_shouldBeValid() async throws {
        // Given
        let server = try XCTUnwrap(server)
        let client = try XCTUnwrap(client)

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
        XCTAssertEqual(
            resolved.session.configuration.secureConnection?.certificateChain,
            .file(fileURL.absolutePath(percentEncoded: false))
        )
    }

    func testCertificates_whenBytes_shouldBeValid() async throws {
        // Given
        let server = try XCTUnwrap(server)
        let client = try XCTUnwrap(client)

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
        XCTAssertEqual(
            resolved.session.configuration.secureConnection?.certificateChain,
            .bytes(bytes)
        )
    }

    func testCertificates_whenAccessBody_shouldBeNever() async throws {
        // Given
        let sut = RequestDL.Certificates {
            RequestDL.Certificate([0, 1, 2])
        }

        // Then
        try await assertNever(sut.body)
    }
}
#endif
