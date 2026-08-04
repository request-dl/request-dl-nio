//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct DynamicValueDeepSearchTests {

    private struct Leaf: DynamicValue {
        let tag: String
    }

    private struct Branch: DynamicValue {
        let leaf = Leaf(tag: "leaf")
    }

    private struct Wrapper: Sendable {
        let branch = Branch()
    }

    @Test
    func callAsFunction_whenValueIsNestedInsideAnotherDynamicValue_findsItRecursively() {
        // Given
        let mirror = DynamicValueMirror(Wrapper())
        let search = DynamicValueDeepSearch<Wrapper>(mirror)

        // When
        let result = search(Leaf.self)

        // Then
        #expect(result.count == 1)
        #expect(result.first?.label == "branch.leaf")
        #expect(result.first?.value.tag == "leaf")
    }
}
