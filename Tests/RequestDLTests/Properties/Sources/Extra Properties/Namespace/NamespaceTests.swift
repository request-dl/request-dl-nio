/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import XCTest
@testable @_spi(Private) import RequestDL

class NamespaceTests: XCTestCase {

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

    func testNamespace_whenNotSet() async throws {
        // Given
        let namespaceID = SendableBox<PropertyNamespace.ID?>(nil)

        // When
        _ = try await resolve(TestProperty {
            NamespaceSpy {
                namespaceID($0)
            }
        })

        // Then
        XCTAssertEqual(namespaceID(), .global)
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

    func testNamespace_whenSet() async throws {
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
        XCTAssertEqual(resolved.request.url, "https://www.apple.com/v1")
        XCTAssertEqual(namespaceID(), PropertyNamespace.ID(
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

    func testNamespace_whenSetWithMultiple() async throws {
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
        XCTAssertEqual(
            resolved.request.url,
            "https://www.apple.com/multiple/namespace"
        )

        XCTAssertEqual(namespaceID(), PropertyNamespace.ID(
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

    func testNamespace_whenModifier() async throws {
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
        XCTAssertEqual(
            resolved.request.url,
            "https://www.apple.com/v1/namespace"
        )

        XCTAssertEqual(namespaceID(), PropertyNamespace.ID(
            base: NamespaceModifier.self,
            namespace: "_namespace"
        ))
    }
}
