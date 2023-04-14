/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersTests: XCTestCase {

    func testMultipleHeadersWithoutGroup() async throws {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.Accept(.json)
            Headers.Origin("127.0.0.1:8080")
            Headers.Any("password", forKey: "xxx-api-key")
        }

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "text/javascript")
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "application/json")
        XCTAssertEqual(request.headers.getValue(forKey: "Origin"), "127.0.0.1:8080")
        XCTAssertEqual(request.headers.getValue(forKey: "xxx-api-key"), "password")
    }

    func testCollisionHeaders() async throws {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.ContentType(.webp)
            Headers.Accept(.jpeg)
            Headers.Any("password", forKey: "xxx-api-key")
            Headers.Any("password123", forKey: "xxx-api-key")
        }

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "image/webp")
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "image/jpeg")
        XCTAssertEqual(request.headers.getValue(forKey: "xxx-api-key"), "password123")
    }

    func testCollisionHeadersWithGroup() async throws {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.Accept(.jpeg)
            Headers.Any("password", forKey: "xxx-api-key")

            HeaderGroup {
                Headers.ContentType(.webp)
                Headers.Any("password123", forKey: "xxx-api-key")
            }
        }

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "image/webp")
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "image/jpeg")
        XCTAssertEqual(request.headers.getValue(forKey: "xxx-api-key"), "password123")
    }

    func testCombinedHeadersWithGroup() async throws {
        let property = TestProperty {
            Headers.Host("127.0.0.1", port: "8080")

            HeaderGroup {
                Headers.ContentType(.webp)
                Headers.Any("password", forKey: "xxx-api-key")
            }

            Headers.Accept(.jpeg)
            Headers.Origin("google.com")
        }

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.headers.getValue(forKey: "Host"), "127.0.0.1:8080")
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "image/webp")
        XCTAssertEqual(request.headers.getValue(forKey: "xxx-api-key"), "password")
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "image/jpeg")
        XCTAssertEqual(request.headers.getValue(forKey: "Origin"), "google.com")
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
        let (_, request) = try await resolve(property)

        // Then
        XCTAssertEqual(request.url, "https://127.0.0.1")
    }
}
