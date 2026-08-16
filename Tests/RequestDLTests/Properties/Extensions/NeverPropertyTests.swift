//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
import RequestDLInternals

struct NeverPropertyTests {

    private struct NeverBuilds: Property {

        var body: some Property {
            if true {
                Internals.preconditionFailure("Never builds")
            }
        }
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = NeverBuilds()

        // Then
        try await assertNever(property.body)
    }
}
