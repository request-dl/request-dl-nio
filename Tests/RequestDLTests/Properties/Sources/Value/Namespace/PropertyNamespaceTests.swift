//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct PropertyNamespaceTests {

    struct WithNamespace: Property {

        @PropertyNamespace var namespace

        var body: some Property {
            EmptyProperty()
        }
    }

    @Test
    func namespace_whenAccessedWithoutGraphTraversal_shouldFallBackToGlobal() {
        // Given
        let property = WithNamespace()

        // When
        let namespace = property.namespace

        // Then
        #expect(namespace == .global)
    }

    @Test
    func namespaceID_whenGlobal_descriptionIsGlobal() {
        #expect(PropertyNamespace.ID.global.description == "global")
    }
}
