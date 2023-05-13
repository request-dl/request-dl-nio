/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class HeadersAnyTests: XCTestCase {

    func testAny_whenInitWithStringValue() async throws {
        // Given
        let name = "xxx-api-key"
        let value = "password"

        // When
        let (_, request) = try await resolve(TestProperty {
            Headers.Any(
                name: name,
                value: value
            )
        })

        // Then
        XCTAssertEqual(request.headers.getValue(forKey: name), value)
    }

    func testAny_whenInitWithLosslessValue() async throws {
        // Given
        let name = "xxx-api-key"
        let value = 123

        // When
        let (_, request) = try await resolve(TestProperty {
            Headers.Any(
                name: name,
                value: value
            )
        })

        // Then
        XCTAssertEqual(request.headers.getValue(forKey: name), "\(value)")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Any(name: "key", value: 123)

        // Then
        try await assertNever(property.body)
    }
}

@available(*, deprecated)
extension HeadersAnyTests {

    func testSingleHeaderAny() async throws {
        let property = TestProperty(Headers.Any("password", forKey: "xxx-api-key"))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "xxx-api-key"), "password")
    }

    func testHeadersAny() async throws {
        let property = TestProperty {
            Headers.Any("text/html", forKey: "Accept")
            Headers.Any("gzip", forKey: "Content-Encoding")
        }

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "text/html")
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Encoding"), "gzip")
    }
}
