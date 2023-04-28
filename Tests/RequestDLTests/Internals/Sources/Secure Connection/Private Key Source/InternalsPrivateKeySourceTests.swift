/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class InternalsPrivateKeySourceTests: XCTestCase {

    var certificate: CertificateResource!

    override func setUp() async throws {
        try await super.setUp()
        certificate = Certificates().client()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        certificate = nil
    }

    func testPrivateKeyByFile() async throws {
        // Given
        let path = certificate.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKeySource.file(path).build()

        // Then
        XCTAssertEqual(resolved, .file(path))
    }

    func testPrivateKeyByRepresentable() async throws {
        // Given
        let path = certificate.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKeySource.privateKey(
            Internals.PrivateKey(path, format: .pem)
        ).build()

        // Then
        XCTAssertEqual(resolved, try .privateKey(.init(file: path, format: .pem)))
    }
}
