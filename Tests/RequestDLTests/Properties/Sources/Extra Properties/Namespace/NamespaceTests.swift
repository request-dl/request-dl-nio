/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import XCTest
@testable @_spi(Private) import RequestDL

@RequestActor
class NamespaceTests: XCTestCase {

    struct NamespaceSpy: Property {

        let callback: (Int, Namespace.ID) -> Void

        var body: Never {
            bodyException()
        }

        @RequestActor
        static func _makeProperty(
            property: _GraphValue<NamespaceTests.NamespaceSpy>,
            inputs: _PropertyInputs
        ) async throws -> _PropertyOutputs {
            let pathway = property._identified.previousValue?.pathway ?? {
                property.pathway
            }()

            property.callback(pathway, inputs.namespaceID)

            return .empty
        }
    }

    func testNamespace_whenNotSet() async throws {
        // Given
        var namespaceID: Namespace.ID?

        // When
        _ = try await resolve(TestProperty {
            NamespaceSpy {
                namespaceID = $1
            }
        })

        // Then
        XCTAssertEqual(namespaceID, .global)
    }
}

extension NamespaceTests {

    struct SingleNamespace<Content: Property>: Property {

        @Namespace var projectNamespace

        let content: Content

        init(@PropertyBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some Property {
            content
            Path("v1")
        }
    }

    func testNamespace_whenSet() async throws {
        // Given
        var namespaceID: Namespace.ID?
        var hashValue: Int = .zero

        // When
        _ = try await resolve(TestProperty {
            SingleNamespace {
                NamespaceSpy {
                    hashValue = $0
                    namespaceID = $1
                }
            }
        })

        // Then
        XCTAssertEqual(namespaceID, Namespace.ID(
            base: SingleNamespace<NamespaceSpy>.self,
            namespace: "_projectNamespace",
            hashValue: hashValue
        ))
    }
}

extension NamespaceTests {

    struct MultipleNamespace<Content: Property>: Property {

        @Namespace var multiple
        @Namespace var namespace

        let content: Content

        init(@PropertyBuilder content: () -> Content) {
            self.content = content()
            print(self)
        }

        var body: some Property {
            content
            Path("v1")
        }
    }

    func testNamespace_whenSetWithMultiple() async throws {
        // Given
        var namespaceID: Namespace.ID?
        var hashValue: Int = .zero

        // When
        _ = try await resolve(TestProperty {
            MultipleNamespace {
                NamespaceSpy {
                    hashValue = $0
                    namespaceID = $1
                }
            }
        })

        // Then
        XCTAssertEqual(namespaceID, Namespace.ID(
            base: MultipleNamespace<NamespaceSpy>.self,
            namespace: "_multiple._namespace",
            hashValue: hashValue
        ))
    }
}

extension NamespaceTests {

    struct NamespaceModifier: PropertyModifier {

        @Namespace var namespace

        let callback: (Int, Namespace.ID) -> Void

        func body(content: Content) -> some Property {
            content
            NamespaceSpy(callback: callback)
        }
    }

    func testNamespace_whenModifier() async throws {
        // Given
        var namespaceID: Namespace.ID?
        var hashValue: Int = .zero

        // When
        _ = try await resolve(TestProperty {
            Path("v1")
                .modifier(NamespaceModifier {
                    hashValue = $0
                    namespaceID = $1
                })
        })

        // Then
        XCTAssertEqual(namespaceID, Namespace.ID(
            base: NamespaceModifier.self,
            namespace: "_namespace",
            hashValue: hashValue
        ))
    }
}


