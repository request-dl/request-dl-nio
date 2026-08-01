//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import Testing

@testable import RequestDL

struct InternalsPrivateKeySourceTests {

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
