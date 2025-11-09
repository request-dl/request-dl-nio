/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable @_spi(Private) import RequestDL

struct NamespaceTests {

    struct NamespaceSpy: Property {

        let callback: @Sendable (PropertyNamespace.ID) -> Void

        var body: Never {
            bodyException()
        }

        static func _makeProperty(
            property: _GraphValue<NamespaceTests.NamespaceSpy>,
            inputs: _PropertyInputs
        ) async throws -> _PropertyOutputs {
            property.callback(inputs.namespaceID)
            return .empty
        }
    }

    @Test
    func namespace_whenNotSet() async throws {
        // Given
        let namespaceID = SendableBox<PropertyNamespace.ID?>(nil)

        // When
        _ = try await resolve(TestProperty {
            NamespaceSpy {
                namespaceID($0)
            }
        })

        // Then
        #expect(namespaceID() == .global)
    }
}

extension NamespaceTests {

    struct SingleNamespace<Content: Property>: Property {

        @PropertyNamespace var v1

        let content: Content

        init(@PropertyBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some Property {
            content
            Path("\(v1)")
        }
    }

    @Test
    func namespace_whenSet() async throws {
        // Given
        let namespaceID = SendableBox<PropertyNamespace.ID?>(nil)

        // When
        let resolved = try await resolve(TestProperty {
            SingleNamespace {
                NamespaceSpy {
                    namespaceID($0)
                }
            }
        })

        // Then
        #expect(resolved.request.url == "https://www.apple.com/v1")
        #expect(namespaceID() == PropertyNamespace.ID(
            base: SingleNamespace<NamespaceSpy>.self,
            namespace: "_v1"
        ))
    }
}

extension NamespaceTests {

    struct MultipleNamespace<Content: Property>: Property {

        @PropertyNamespace var multiple
        @PropertyNamespace var namespace

        let content: Content

        init(@PropertyBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some Property {
            content
            Path("\(multiple)/\(namespace)")
        }
    }

    @Test
    func namespace_whenSetWithMultiple() async throws {
        // Given
        let namespaceID = SendableBox<PropertyNamespace.ID?>(nil)

        // When
        let resolved = try await resolve(TestProperty {
            MultipleNamespace {
                NamespaceSpy {
                    namespaceID($0)
                }
            }
        })

        // Then
        #expect(
            resolved.request.url == "https://www.apple.com/multiple/namespace"
        )

        #expect(namespaceID() == PropertyNamespace.ID(
            base: MultipleNamespace<NamespaceSpy>.self,
            namespace: "_multiple._namespace"
        ))
    }
}

extension NamespaceTests {

    struct NamespaceModifier: PropertyModifier {

        @PropertyNamespace var namespace

        let callback: @Sendable (PropertyNamespace.ID) -> Void

        func body(content: Content) -> some Property {
            content
            Path("\(namespace)")
            NamespaceSpy(callback: callback)
        }
    }

    @Test
    func namespace_whenModifier() async throws {
        // Given
        let namespaceID = SendableBox<PropertyNamespace.ID?>(nil)

        // When
        let resolved = try await resolve(TestProperty {
            Path("v1")
                .modifier(NamespaceModifier {
                    namespaceID($0)
                })
        })

        // Then
        #expect(
            resolved.request.url == "https://www.apple.com/v1/namespace"
        )

        #expect(namespaceID() == PropertyNamespace.ID(
            base: NamespaceModifier.self,
            namespace: "_namespace"
        ))
    }
}
