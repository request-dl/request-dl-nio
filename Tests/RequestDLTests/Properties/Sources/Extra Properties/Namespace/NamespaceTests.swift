//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
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
        let namespaceID = InlineProperty<PropertyNamespace.ID?>(wrappedValue: nil)

        // When
        _ = try await resolve(
            TestProperty {
                NamespaceSpy {
                    namespaceID.wrappedValue = $0
                }
            }
        )

        // Then
        #expect(namespaceID.wrappedValue == .global)
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
        let namespaceID = InlineProperty<PropertyNamespace.ID?>(wrappedValue: nil)

        // When
        let resolved = try await resolve(
            TestProperty {
                SingleNamespace {
                    NamespaceSpy {
                        namespaceID.wrappedValue = $0
                    }
                }
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://www.apple.com/SingleNamespace<NamespaceSpy>.v1")
        #expect(
            namespaceID.wrappedValue
                == PropertyNamespace.ID(
                    base: SingleNamespace<NamespaceSpy>.self,
                    namespace: "_v1"
                )
        )
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

            // Emitted separately on purpose. Both wrappers describe the same merged namespace,
            // so the two segments have to come out identical. They only differed before because
            // the first wrapper was left holding a prefix of the real namespace.
            Path("\(multiple)")
            Path("\(namespace)")
        }
    }

    @Test
    func namespace_whenSetWithMultiple() async throws {
        // Given
        let namespaceID = InlineProperty<PropertyNamespace.ID?>(wrappedValue: nil)

        // When
        let resolved = try await resolve(
            TestProperty {
                MultipleNamespace {
                    NamespaceSpy {
                        namespaceID.wrappedValue = $0
                    }
                }
            }
        )

        // Then
        let expected = PropertyNamespace.ID(
            base: MultipleNamespace<NamespaceSpy>.self,
            namespace: "_multiple._namespace"
        )

        #expect(namespaceID.wrappedValue == expected)

        // Derived rather than spelled out, so the repetition reads as the assertion it is.
        #expect(resolved.requestConfiguration.url == "https://www.apple.com/\(expected)/\(expected)")
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
        let namespaceID = InlineProperty<PropertyNamespace.ID?>(wrappedValue: nil)

        // When
        let resolved = try await resolve(
            TestProperty {
                Path("v1")
                    .modifier(
                        NamespaceModifier {
                            namespaceID.wrappedValue = $0
                        }
                    )
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://www.apple.com/v1/NamespaceModifier.namespace"
        )

        #expect(
            namespaceID.wrappedValue
                == PropertyNamespace.ID(
                    base: NamespaceModifier.self,
                    namespace: "_namespace"
                )
        )
    }
}
