/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class GroupTests: XCTestCase {

    func testSingleGroup() async throws {
        // Given
        let property = Group {
            BaseURL("google.com")
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        XCTAssertEqual(resolved.request.url, "https://google.com")
    }

    func testMultipleGroup() async throws {
        // Given
        let property = Group {
            BaseURL("google.com")
            Path("api/v1")
            Query("all", forKey: "available_methods")
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        XCTAssertEqual(
            resolved.request.url,
            "https://google.com/api/v1?available_methods=all"
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = Group {}

        // Then
        try await assertNever(property.body)
    }
}
