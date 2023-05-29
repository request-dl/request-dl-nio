/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class PropertyModifierTests: XCTestCase {

    struct CustomModifier: PropertyModifier {

        let includesContent: Bool

        func body(content: Content) -> some Property {
            PropertyGroup {
                if includesContent {
                    content
                } else {
                    BaseURL("google.com")
                }

                Path("api")
                Path("v2")
            }

            Query(name: "id", value: 123)
        }
    }

    func testModifier_whenIncludesContent() async throws {
        // Given
        let modifier = CustomModifier(includesContent: true)

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("apple.com")
                .modifier(modifier)
        })

        // Then
        XCTAssertEqual(
            resolved.request.url,
            "https://apple.com/api/v2?id=123"
        )
    }

    func testModifier_whenNotIncludesContent() async throws {
        // Given
        let modifier = CustomModifier(includesContent: false)

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("apple.com")
                .modifier(modifier)
        })

        // Then
        XCTAssertEqual(
            resolved.request.url,
            "https://google.com/api/v2?id=123"
        )
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
        let resolved = try await resolve(TestProperty {
            SecureConnection {
                Certificate(certificatePath)
                    .modifier(AdditionalTrustsFaker())
            }
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.additionalTrustRoots, [
            .certificates([.init(certificatePath, format: .pem)])
        ])
    }
}

extension PropertyModifierTests {

    struct PathEnvironmentKey: PropertyEnvironmentKey {
        static var defaultValue: String?
    }

    struct PathModifier: PropertyModifier {

        @PropertyEnvironment(\.path) var path

        func body(content: Content) -> some Property {
            content

            if let path {
                Path(path)
            }
        }
    }

    func testModifier_whenPathEnvironmentSet() async throws {
        // Given
        let additionalPath = "api"
        let modifier = PathModifier()

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("www.google.com")
                .modifier(modifier)
                .environment(\.path, additionalPath)
        })

        // Then
        XCTAssertEqual(
            resolved.request.url,
            "https://www.google.com/\(additionalPath)"
        )
    }

    func testModifier_whenPathEnvironmentIsNotSet() async throws {
        // Given
        let modifier = PathModifier()

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("www.google.com")
                .modifier(modifier)
        })

        // Then
        XCTAssertEqual(
            resolved.request.url,
            "https://www.google.com"
        )
    }
}

extension PropertyEnvironmentValues {

    fileprivate var path: String? {
        get { self[PropertyModifierTests.PathEnvironmentKey.self] }
        set { self[PropertyModifierTests.PathEnvironmentKey.self] = newValue }
    }
}
