/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class PropertyModifierTests: XCTestCase {

    struct CustomModifier: PropertyModifier {

        let includesContent: Bool

        func body(content: Content) -> some Property {
            Group {
                if includesContent {
                    content
                } else {
                    BaseURL("google.com")
                }

                Path("api")
                Path("v2")
            }

            Query(123, forKey: "id")
        }
    }

    func testModifier_whenIncludesContent() async throws {
        // Given
        let modifier = CustomModifier(includesContent: true)

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("apple.com")
                .modifier(modifier)
        })

        // Then
        XCTAssertEqual(request.url, "https://apple.com/api/v2?id=123")
    }

    func testModifier_whenNotIncludesContent() async throws {
        // Given
        let modifier = CustomModifier(includesContent: false)

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("apple.com")
                .modifier(modifier)
        })

        // Then
        XCTAssertEqual(request.url, "https://google.com/api/v2?id=123")
    }
}

extension PropertyModifierTests {

    struct AdditionalTrustsFaker: PropertyModifier {

        func body(content: Content) -> some Property {
            content
                .environment(\.certificateProperty, .additionalTrust)
        }
    }

    func testModifier_whenSecureConnectionFaker() async throws {
        // Given
        let resource = Certificates().server()
        let certificatePath = resource.certificateURL.absolutePath(percentEncoded: false)

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection {
                Certificate(certificatePath)
                    .modifier(AdditionalTrustsFaker())
            }
        })

        let sut = session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.additionalTrustRoots, [
            .certificates([.init(certificatePath, format: .pem)])
        ])
    }
}
