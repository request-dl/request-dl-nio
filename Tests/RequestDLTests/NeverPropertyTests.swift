/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class NeverPropertyTests: XCTestCase {

    private struct NeverBuilds: Property {

        var body: some Property {
            if true {
                fatalError("Never builds")
            }
        }
    }

    func testNeverBody() async throws {
        // Given
        let property = NeverBuilds()

        // Then
        try await assertNever(property.body)
    }
}