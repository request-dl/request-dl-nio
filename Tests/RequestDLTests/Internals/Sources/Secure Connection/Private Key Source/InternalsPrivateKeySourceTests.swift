/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOSSL
@testable import RequestDL

struct InternalsPrivateKeySourceTests {

    @Test
    func privateKeyByFile() async throws {
        // Given
        let certificate = Certificates().client()
        let path = certificate.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKeySource.file(path).build()

        // Then
        #expect(resolved == .file(path))
    }

    @Test
    func privateKeyByRepresentable() async throws {
        // Given
        let certificate = Certificates().client()
        let path = certificate.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKeySource.privateKey(
            Internals.PrivateKey(path, format: .pem)
        ).build()

        // Then
        let expectedSource: NIOSSL.NIOSSLPrivateKeySource = try .privateKey(.init(file: path, format: .pem))
        #expect(resolved == expectedSource)
    }
}
