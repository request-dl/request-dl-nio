/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class _OptionalContentTests: XCTestCase {

    func testConditionActiveBuilder() async throws {
        // Given
        let applyCondition = true

        @PropertyBuilder
        var result: some Property {
            if applyCondition {
                BaseURL("google.com")
            }
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _OptionalContent<BaseURL>)
        XCTAssertEqual(resolved.request.url, "https://google.com")
        XCTAssertTrue(resolved.request.headers.isEmpty)
    }

    func testConditionDisableBuilder() async throws {
        // Given
        let applyCondition = false

        @PropertyBuilder
        var result: some Property {
            if applyCondition {
                BaseURL("google.com")
            }
        }

        // When
        let resolved = try await resolve(TestProperty(result))

        // Then
        XCTAssertTrue(result is _OptionalContent<BaseURL>)
        XCTAssertNotEqual(resolved.request.url, "https://google.com")
    }

    func testNeverBody() async throws {
        // Given
        let property = _OptionalContent<EmptyProperty>(.init())

        // Then
        try await assertNever(property.body)
    }
}
