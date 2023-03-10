/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class _OptionalContentTests: XCTestCase {

    func testConditionActiveBuilder() async {
        // Given
        let applyCondition = true

        @PropertyBuilder
        var result: some Property {
            if applyCondition {
                BaseURL("google.com")
            }
        }

        // When
        let (_, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _OptionalContent<BaseURL>)
        XCTAssertEqual(request.url?.absoluteString, "https://google.com")
        XCTAssertNil(request.allHTTPHeaderFields)
    }

    func testConditionDisableBuilder() async {
        // Given
        let applyCondition = false

        @PropertyBuilder
        var result: some Property {
            if applyCondition {
                BaseURL("google.com")
            }
        }

        // When
        let (_, request) = await resolve(TestProperty(result))

        // Then
        XCTAssertTrue(result is _OptionalContent<BaseURL>)
        XCTAssertNotEqual(request.url?.absoluteString, "https://google.com")
    }

    func testNeverBody() async throws {
        // Given
        let property = _OptionalContent<EmptyProperty>(.init())

        // Then
        try await assertNever(property.body)
    }
}