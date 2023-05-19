/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class HeadersTests: XCTestCase {

    func testMultipleHeadersWithoutGroup() async throws {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.Accept(.json)
            Headers.Origin("127.0.0.1:8080")
            Headers.Any(name: "xxx-api-key", value: "password")
        }

        let resolved = try await resolve(property)

        XCTAssertEqual(resolved.request.headers["Content-Type"], ["text/javascript"])
        XCTAssertEqual(resolved.request.headers["Accept"], ["application/json"])
        XCTAssertEqual(resolved.request.headers["Origin"], ["127.0.0.1:8080"])
        XCTAssertEqual(resolved.request.headers["xxx-api-key"], ["password"])
    }

    func testCollisionHeaders() async throws {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.ContentType(.webp)
            Headers.Accept(.jpeg)
            Headers.Any(name: "xxx-api-key", value: "password")
            Headers.Any(name: "xxx-api-key", value: "password123")
        }

        let resolved = try await resolve(property)

        XCTAssertEqual(resolved.request.headers["Content-Type"], ["image/webp"])
        XCTAssertEqual(resolved.request.headers["Accept"], ["image/jpeg"])
        XCTAssertEqual(resolved.request.headers["xxx-api-key"], ["password123"])
    }

    func testCollisionHeadersWithGroup() async throws {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.Accept(.jpeg)
            Headers.Any(name: "xxx-api-key", value: "password")

            HeaderGroup {
                Headers.ContentType(.webp)
                Headers.Any(name: "xxx-api-key", value: "password123")
            }
        }

        let resolved = try await resolve(property)

        XCTAssertEqual(resolved.request.headers["Content-Type"], ["image/webp"])
        XCTAssertEqual(resolved.request.headers["Accept"], ["image/jpeg"])
        XCTAssertEqual(resolved.request.headers["xxx-api-key"], ["password123"])
    }

    func testCombinedHeadersWithGroup() async throws {
        let property = TestProperty {
            Headers.Host("127.0.0.1", port: "8080")

            HeaderGroup {
                Headers.ContentType(.webp)
                Headers.Any(name: "xxx-api-key", value: "password")
            }

            Headers.Accept(.jpeg)
            Headers.Origin("google.com")
        }

        let resolved = try await resolve(property)

        XCTAssertEqual(resolved.request.headers["Host"], ["127.0.0.1:8080"])
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["image/webp"])
        XCTAssertEqual(resolved.request.headers["xxx-api-key"], ["password"])
        XCTAssertEqual(resolved.request.headers["Accept"], ["image/jpeg"])
        XCTAssertEqual(resolved.request.headers["Origin"], ["google.com"])
    }

    func testInvalidGroup() async throws {
        // Given
        let property = TestProperty {
            BaseURL("127.0.0.1")
            HeaderGroup {
                Query("password", forKey: "api_key")
            }
        }

        // When
        let resolved = try await resolve(property)

        // Then
        XCTAssertEqual(resolved.request.url, "https://127.0.0.1")
    }
}
