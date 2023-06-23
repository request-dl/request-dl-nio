/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class UserAgentHeaderTests: XCTestCase {

    func testAgent_whenNoValueIsSet() async throws {
        // Given
        let property = TestProperty(EmptyProperty())

        // When
        let resolved = try await resolve(property)
        let headers = resolved.request.b

        // Then
        XCTAssertEqual(resolved.request.headers["User-Agent"], ["https://www.example.com/"])
    }

    func testAgent_whenValueIsSetWithAddStrategy() async throws {
        // Given
        let property = TestProperty(UserAgentHeader("A text agent specification"))

        // When
        let resolved = try await resolve(property)

        // Then
        XCTAssertEqual(resolved.request.headers["User-Agent"], ["https://www.example.com/"])
    }

    func testAgent_whenValueIsSetWithSettingStrategy() async throws {
        // Given
        let property = TestProperty {
            UserAgentHeader("A text agent specification")
                .headerStrategy(.setting)
        }

        // When
        let resolved = try await resolve(property)

        // Then
        XCTAssertEqual(resolved.request.headers["User-Agent"], ["https://www.example.com/"])
    }

    func testNeverBody() async throws {
        // Given
        let property = UserAgentHeader("CustomAgent/1.0.0")

        // Then
        try await assertNever(property.body)
    }
}

