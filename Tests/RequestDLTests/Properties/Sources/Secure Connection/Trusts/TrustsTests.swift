/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class TrustsTests: XCTestCase {

    var client: CertificateResource?
    var server: CertificateResource?

    override func setUp() async throws {
        try await super.setUp()
        client = Certificates().client()
        server = Certificates().server()
    }

    func testTrusts_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = try Array(Data(contentsOf: XCTUnwrap(server).certificateURL))
        let client = try XCTUnwrap(client)

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
        XCTAssertFalse(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true)
        XCTAssertEqual(
            resolved.session.configuration.secureConnection?.trustRoots,
            .certificates([
                .init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
                .init(server, format: .pem)
            ])
        )
    }

    func testTrusts_whenFile_shouldBeValid() async throws {
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
                RequestDL.Trusts(fileURL.absolutePath(percentEncoded: false))
            }
        })

        // Then
        XCTAssertFalse(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true)
        XCTAssertEqual(
            resolved.session.configuration.secureConnection?.trustRoots,
            .file(fileURL.absolutePath(percentEncoded: false))
        )
    }

    func testTrusts_whenBytes_shouldBeValid() async throws {
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
                RequestDL.Trusts(bytes)
            }
        })

        // Then
        XCTAssertFalse(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true)
        XCTAssertEqual(
            resolved.session.configuration.secureConnection?.trustRoots,
            .bytes(bytes)
        )
    }

    func testTrusts_whenAccessBody_shouldBeNever() async throws {
        // Given
        let sut = RequestDL.Trusts {
            RequestDL.Certificate([0, 1, 2])
        }

        // Then
        try await assertNever(sut.body)
    }
}
