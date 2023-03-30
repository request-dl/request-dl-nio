/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDLInternals
@testable import RequestDL

class TrustsTests: XCTestCase {

    var client: CertificateResource!
    var server: CertificateResource!

    override func setUp() async throws {
        try await super.setUp()
        client = RequestDLInternals.Certificates().client()
        server = RequestDLInternals.Certificates().server()
    }

    func testTrusts_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = try Array(Data(contentsOf: server.certificateURL))

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Trusts {
                    RequestDL.Certificate(client.certificateURL.absolutePath())
                    RequestDL.Certificate(server)
                }
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.trustRoots,
            .certificates([
                .init(client.certificateURL.absolutePath()),
                .init(server)
            ])
        )
    }

    func testTrusts_whenFile_shouldBeValid() async throws {
        // Given
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
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Trusts(fileURL.absolutePath())
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.trustRoots,
            .file(fileURL.absolutePath())
        )
    }

    func testTrusts_whenBytes_shouldBeValid() async throws {
        // Given
        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let bytes = Array(data)

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Trusts(bytes)
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.trustRoots,
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