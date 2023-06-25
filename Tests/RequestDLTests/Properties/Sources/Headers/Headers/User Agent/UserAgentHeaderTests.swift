/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import AsyncHTTPClient
@testable import RequestDL

class UserAgentHeaderTests: XCTestCase {

    func testAgent_whenNoValueIsSet() async throws {
        // Given
        let property = TestProperty(EmptyProperty())

        // When
        let resolved = try await resolve(property)

        // Then
        XCTAssertNil(resolved.request.headers["User-Agent"])
    }

    func testAgent_whenValueIsSetWithAddStrategy() async throws {
        // Given
        let userAgent = "A text agent specification"

        // When
        let resolved = try await resolve(TestProperty {
            UserAgentHeader(userAgent)
        })

        // Then
        XCTAssertEqual(resolved.request.headers["User-Agent"], [userAgent])
    }

    func testAgent_whenUsingDefaultValue() async throws {
        // Given
        let property = TestProperty {
            UserAgentHeader()
        }

        // When
        let resolved = try await resolve(property)

        // Then
        XCTAssertEqual(resolved.request.headers["User-Agent"], [ProcessInfo.processInfo.userAgent])
    }

    func testAgent_whenUsingDefaultValueWithCustomAgent() async throws {
        // Given
        let userAgent = "CustomAgent"
        // When
        let resolved = try await resolve(TestProperty {
            HeaderGroup {
                UserAgentHeader()
                UserAgentHeader(userAgent)
            }
            .headerStrategy(.adding)
        })

        // Then
        XCTAssertEqual(
            resolved.request.headers["User-Agent"],
            [ProcessInfo.processInfo.userAgent + " \(userAgent)"]
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = UserAgentHeader("CustomAgent/1.0.0")

        // Then
        try await assertNever(property.body)
    }
}

