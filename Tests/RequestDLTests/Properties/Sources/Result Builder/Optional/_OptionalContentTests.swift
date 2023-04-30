/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
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
        let (_, request) = try await resolve(result)

        // Then
        XCTAssertTrue(result is _OptionalContent<BaseURL>)
        XCTAssertEqual(request.url, "https://google.com")
        XCTAssertTrue(request.headers.isEmpty)
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
        let (_, request) = try await resolve(TestProperty(result))

        // Then
        XCTAssertTrue(result is _OptionalContent<BaseURL>)
        XCTAssertNotEqual(request.url, "https://google.com")
    }

    func testNeverBody() async throws {
        // Given
        let property = _OptionalContent<EmptyProperty>(.init())

        // Then
        try await assertNever(property.body)
    }
}
