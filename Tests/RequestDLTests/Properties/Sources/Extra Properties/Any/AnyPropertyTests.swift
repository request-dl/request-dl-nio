/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct AnyPropertyTests {

    @Test
    func anyPropertyErasingQuery() async throws {
        // Given
        let property = Query(name: "number", value: 123)

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            AnyProperty(property)
        })

        // Then
        #expect(resolved.request.url == "https://127.0.0.1?number=123")
    }

    @Test
    func anyProperty_whenCertificate() async throws {
        // Given
        let certificate = Certificates().server()
        let path = certificate.certificateURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try await resolve(TestProperty {
            SecureConnection {
                AdditionalTrusts {
                    AnyProperty(Certificate(path))
                }
            }
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        #expect(sut?.additionalTrustRoots == [
            .certificates([.init(path, format: .pem)])
        ])
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = AnyProperty(EmptyProperty())

        // Then
        try await assertNever(property.body)
    }
}
