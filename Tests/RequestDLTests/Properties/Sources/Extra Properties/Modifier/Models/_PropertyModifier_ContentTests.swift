//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct _PropertyModifier_ContentTests {

    struct DummyModifier: PropertyModifier {

        func body(content: Content) -> some Property {
            content
        }
    }

    @Test func neverBody() async throws {
        // Given
        let property = _PropertyModifier_Content<DummyModifier>({ _, _ in .empty })

        // Then
        try await assertNever(property.body)
    }
}
