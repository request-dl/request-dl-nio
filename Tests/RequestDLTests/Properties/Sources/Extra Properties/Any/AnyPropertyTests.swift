/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class AnyPropertyTests: XCTestCase {

    func testAnyPropertyErasingQuery() async throws {
        // Given
        let property = Query(123, forKey: "number")

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            AnyProperty(property)
        })

        // Then
        XCTAssertEqual(request.url, "https://127.0.0.1?number=123")
    }

    func testAnyProperty_whenCertificate() async throws {
        // Given
        let certificate = Certificates().server()
        let path = certificate.certificateURL.absolutePath(percentEncoded: false)

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection {
                AdditionalTrusts {
                    AnyProperty(Certificate(path))
                }
            }
        })

        let sut = session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.additionalTrustRoots, [
            .certificates([.init(path, format: .pem)])
        ])
    }

    func testNeverBody() async throws {
        // Given
        let property = AnyProperty(EmptyProperty())

        // Then
        try await assertNever(property.body)
    }
}
