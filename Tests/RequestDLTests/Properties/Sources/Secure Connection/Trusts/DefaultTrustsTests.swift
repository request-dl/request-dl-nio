/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class DefaultTrustsTests: XCTestCase {

    func testTrusts_whenDefault_shouldBeDefault() async throws {
        // Given
        let property = DefaultTrusts()

        // When
        let resolved = try await resolve(TestProperty {
            SecureConnection {
                property
            }
        })

        // Then
        XCTAssertEqual(
            resolved.session.configuration.secureConnection?.trustRoots,
            .default
        )
    }
}
