/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct NeverPropertyTests {

    private struct NeverBuilds: Property {

        var body: some Property {
            if true {
                Internals.Log.failure("Never builds")
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
