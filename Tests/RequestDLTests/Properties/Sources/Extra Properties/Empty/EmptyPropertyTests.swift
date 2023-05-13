/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class EmptyPropertyTests: XCTestCase {

    func testEmptyBuilder() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            // swiftlint:disable redundant_discardable_let
            let _ = 1
            // swiftlint:enable redundant_discardable_let
        }

        // When
        _ = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is EmptyProperty)
    }

    func testEmptyExplicitBuilder() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            EmptyProperty()
        }

        // When
        _ = try await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is EmptyProperty)
    }

    func testNeverBody() async throws {
        // Given
        let property = EmptyProperty()

        // Then
        try await assertNever(property.body)
    }
}
