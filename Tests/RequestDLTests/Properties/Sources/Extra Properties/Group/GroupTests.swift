/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class GroupTests: XCTestCase {

    func testSingleGroup() async throws {
        // Given
        let property = PropertyGroup {
            BaseURL("google.com")
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        XCTAssertEqual(resolved.request.url, "https://google.com")
    }

    func testMultipleGroup() async throws {
        // Given
        let property = PropertyGroup {
            BaseURL("google.com")
            Path("api/v1")
            Query(name: "available_methods", value: "all")
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
        let property = PropertyGroup {}

        // Then
        try await assertNever(property.body)
    }
}
