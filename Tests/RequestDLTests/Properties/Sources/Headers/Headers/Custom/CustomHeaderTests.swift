/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class CustomHeaderTests: XCTestCase {

    func testAny_whenInitWithStringValue() async throws {
        // Given
        let name = "xxx-api-key"
        let value = "password"

        // When
        let resolved = try await resolve(TestProperty {
            CustomHeader(
                name: name,
                value: value
            )
        })

        // Then
        XCTAssertEqual(resolved.request.headers[name], [value])
    }

    func testAny_whenInitWithLosslessValue() async throws {
        // Given
        let name = "xxx-api-key"
        let value = 123

        // When
        let resolved = try await resolve(TestProperty {
            CustomHeader(
                name: name,
                value: value
            )
        })

        // Then
        XCTAssertEqual(resolved.request.headers[name], ["\(value)"])
    }

    func testNeverBody() async throws {
        // Given
        let property = CustomHeader(name: "key", value: 123)

        // Then
        try await assertNever(property.body)
    }
}

@available(*, deprecated)
extension CustomHeaderTests {

    func testSingleHeaderAny() async throws {
        let property = TestProperty(CustomHeader("password", forKey: "xxx-api-key"))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["xxx-api-key"], ["password"])
    }

    func testHeadersAny() async throws {
        let property = TestProperty {
            CustomHeader("text/html", forKey: "Accept")
            CustomHeader("gzip", forKey: "Content-Encoding")
        }

        let resolved = try await resolve(property)

        XCTAssertEqual(resolved.request.headers["Accept"], ["text/html"])
        XCTAssertEqual(resolved.request.headers["Content-Encoding"], ["gzip"])
    }
}
