/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct PropertyModifierTests {

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

    @Test
    func modifier_whenIncludesContent() async throws {
        // Given
        let modifier = CustomModifier(includesContent: true)

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("apple.com")
                .modifier(modifier)
        })

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://apple.com/api/v2?id=123"
        )
    }

    @Test
    func modifier_whenNotIncludesContent() async throws {
        // Given
        let modifier = CustomModifier(includesContent: false)

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("apple.com")
                .modifier(modifier)
        })

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://google.com/api/v2?id=123"
        )
    }
}

extension PropertyModifierTests {

    struct AdditionalTrustRootsFaker: PropertyModifier {

        func body(content: Content) -> some Property {
            content
                .environment(\.certificateProperty, .additionalTrust)
        }
    }

    @Test
    func modifier_whenSecureConnectionFaker() async throws {
        // Given
        let resource = Certificates().server()
        let certificatePath = resource.certificateURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try await resolve(TestProperty {
            SecureConnection {
                Certificate(certificatePath)
                    .modifier(AdditionalTrustRootsFaker())
            }
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        #expect(sut?.additionalTrustRoots == [
            .certificates([.init(certificatePath, format: .pem)])
        ])
    }
}

extension PropertyModifierTests {

    struct PathEnvironmentKey: RequestEnvironmentKey {
        static var defaultValue: String? { nil }
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

    @Test
    func modifier_whenPathEnvironmentSet() async throws {
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
        #expect(
            resolved.requestConfiguration.url == "https://www.google.com/\(additionalPath)"
        )
    }

    @Test
    func modifier_whenPathEnvironmentIsNotSet() async throws {
        // Given
        let modifier = PathModifier()

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("www.google.com")
                .modifier(modifier)
        })

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://www.google.com"
        )
    }
}

extension RequestEnvironmentValues {

    fileprivate var path: String? {
        get { self[PropertyModifierTests.PathEnvironmentKey.self] }
        set { self[PropertyModifierTests.PathEnvironmentKey.self] = newValue }
    }
}
