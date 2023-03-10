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
            Headers.Origin("localhost:8080")
            Headers.Any("password", forKey: "xxx-api-key")
        }

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/javascript")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "localhost:8080")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password")
    }

    func testCollisionHeaders() async {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.ContentType(.webp)
            Headers.Accept(.jpeg)
            Headers.Any("password", forKey: "xxx-api-key")
            Headers.Any("password123", forKey: "xxx-api-key")
        }

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/webp")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/jpeg")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password123")
    }

    func testCollisionHeadersWithGroup() async {
        let property = TestProperty {
            Headers.ContentType(.javascript)
            Headers.Accept(.jpeg)
            Headers.Any("password", forKey: "xxx-api-key")

            HeaderGroup {
                Headers.ContentType(.webp)
                Headers.Any("password123", forKey: "xxx-api-key")
            }
        }

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/webp")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/jpeg")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password123")
    }

    func testCombinedHeadersWithGroup() async {
        let property = TestProperty {
            Headers.Host("localhost", port: "8080")

            HeaderGroup {
                Headers.ContentType(.webp)
                Headers.Any("password", forKey: "xxx-api-key")
            }

            Headers.Accept(.jpeg)
            Headers.Origin("google.com")
        }

        let (_, request) = await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Host"), "localhost:8080")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/webp")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/jpeg")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "google.com")
    }

    func testInvalidGroup() async {
        // Given
        let property = TestProperty {
            BaseURL("localhost")
            HeaderGroup {
                Query("password", forKey: "api_key")
            }
        }

        // When
        let (_, request) = await resolve(property)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://localhost")
    }
}
