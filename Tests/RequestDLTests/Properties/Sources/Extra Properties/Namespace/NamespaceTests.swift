/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import XCTest
@testable @_spi(Private) import RequestDL

@RequestActor
class NamespaceTests: XCTestCase {

    struct NamespaceSpy: Property {

        let callback: (Namespace.ID) -> Void

        var body: Never {
            bodyException()
        }

        @RequestActor
        static func _makeProperty(
            property: _GraphValue<NamespaceTests.NamespaceSpy>,
            inputs: _PropertyInputs
        ) async throws -> _PropertyOutputs {
            property.callback(inputs.namespaceID)
            return .empty
        }
    }

    func testNamespace_whenNotSet() async throws {
        // Given
        var namespaceID: Namespace.ID?

        // When
        _ = try await resolve(TestProperty {
            NamespaceSpy {
                namespaceID = $0
            }
        })

        // Then
        XCTAssertEqual(namespaceID, .global)
    }
}

extension NamespaceTests {

    struct SingleNamespace<Content: Property>: Property {

        @Namespace var v1

        let content: Content

        init(@PropertyBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some Property {
            content
            Path("\(v1)")
        }
    }

    func testNamespace_whenSet() async throws {
        // Given
        var namespaceID: Namespace.ID?

        // When
        let (_, request) = try await resolve(TestProperty {
            SingleNamespace {
                NamespaceSpy {
                    namespaceID = $0
                }
            }
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com/v1")
        XCTAssertEqual(namespaceID, Namespace.ID(
            base: SingleNamespace<NamespaceSpy>.self,
            namespace: "_v1"
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
        }

        var body: some Property {
            content
            Path("\(multiple)/\(namespace)")
        }
    }

    func testNamespace_whenSetWithMultiple() async throws {
        // Given
        var namespaceID: Namespace.ID?

        // When
        let (_, request) = try await resolve(TestProperty {
            MultipleNamespace {
                NamespaceSpy {
                    namespaceID = $0
                }
            }
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com/multiple/namespace")
        XCTAssertEqual(namespaceID, Namespace.ID(
            base: MultipleNamespace<NamespaceSpy>.self,
            namespace: "_multiple._namespace"
        ))
    }
}

extension NamespaceTests {

    struct NamespaceModifier: PropertyModifier {

        @Namespace var namespace

        let callback: (Namespace.ID) -> Void

        func body(content: Content) -> some Property {
            content
            Path("\(namespace)")
            NamespaceSpy(callback: callback)
        }
    }

    func testNamespace_whenModifier() async throws {
        // Given
        var namespaceID: Namespace.ID?

        // When
        let (_, request) = try await resolve(TestProperty {
            Path("v1")
                .modifier(NamespaceModifier {
                    namespaceID = $0
                })
        })

        // Then
        XCTAssertEqual(request.url, "https://www.apple.com/v1/namespace")
        XCTAssertEqual(namespaceID, Namespace.ID(
            base: NamespaceModifier.self,
            namespace: "_namespace"
        ))
    }
}
