/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class HeadersTests: XCTestCase {

    func testHeaders_whenMultipleHeadersWithoutGroup() async throws {
        let property = TestProperty {
            CacheHeader()
                .public(true)
            AcceptHeader(.json)
            OriginHeader("127.0.0.1:8080")
            CustomHeader(name: "xxx-api-key", value: "password")
        }

        let resolved = try await resolve(property)

        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
        XCTAssertEqual(resolved.request.headers["Accept"], ["application/json"])
        XCTAssertEqual(resolved.request.headers["Origin"], ["127.0.0.1:8080"])
        XCTAssertEqual(resolved.request.headers["xxx-api-key"], ["password"])
    }

    func testHeaders_whenSameHeaderSpecifyWithSettingStrategy() async throws {
        let property = TestProperty {
            CacheHeader()
                .public(true)

            CacheHeader()
                .proxyRevalidate()

            AcceptHeader(.jpeg)
            CustomHeader(name: "xxx-api-key", value: "password")
            CustomHeader(name: "xxx-api-key", value: "password123")
        }

        let resolved = try await resolve(property)

        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["proxy-revalidate"])
        XCTAssertEqual(resolved.request.headers["Accept"], ["image/jpeg"])
        XCTAssertEqual(resolved.request.headers["xxx-api-key"], ["password123"])
    }

    func testHeaders_whenSameHeaderWithGroupWithSettingStrategy() async throws {
        let property = TestProperty {
            CacheHeader()
                .public(true)

            AcceptHeader(.jpeg)
            CustomHeader(name: "xxx-api-key", value: "password")

            HeaderGroup {
                CacheHeader()
                    .proxyRevalidate()

                CustomHeader(name: "xxx-api-key", value: "password123")
            }
        }

        let resolved = try await resolve(property)

        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["proxy-revalidate"])
        XCTAssertEqual(resolved.request.headers["Accept"], ["image/jpeg"])
        XCTAssertEqual(resolved.request.headers["xxx-api-key"], ["password123"])
    }

    func testHeaders_whenSameHeaderSpecifyWithAddingStrategy() async throws {
        // Given
        let property = TestProperty {
            CacheHeader()
                .public(true)

            CacheHeader()
                .proxyRevalidate()

            AcceptHeader(.jpeg)

            CustomHeader(name: "xxx-api-key", value: "password")
            CustomHeader(name: "xxx-api-key", value: "password123")
        }
        .headerStrategy(.adding)

        // When
        let resolved = try await resolve(property)

        // Then
        XCTAssertEqual(
            resolved.request.headers["Cache-Control"],
            ["public,proxy-revalidate"]
        )

        XCTAssertEqual(resolved.request.headers["Accept"], ["image/jpeg"])

        XCTAssertEqual(
            resolved.request.headers["xxx-api-key"],
            ["password", "password123"]
        )
    }

    func testHeaders_whenSameHeaderWithGroupWithAddingStrategy() async throws {
        // Given
        let property = TestProperty {
            CacheHeader()
                .public(true)

            AcceptHeader(.jpeg)
            CustomHeader(name: "xxx-api-key", value: "password")

            HeaderGroup {
                CacheHeader()
                    .proxyRevalidate()

                CustomHeader(name: "xxx-api-key", value: "password123")
            }
        }
        .headerStrategy(.adding)

        // When
        let resolved = try await resolve(property)

        // Then
        XCTAssertEqual(
            resolved.request.headers["Cache-Control"],
            ["public,proxy-revalidate"]
        )

        XCTAssertEqual(resolved.request.headers["Accept"], ["image/jpeg"])

        XCTAssertEqual(
            resolved.request.headers["xxx-api-key"],
            ["password", "password123"]
        )
    }

    func testHeaders_whenCombinedHeadersWithGroup() async throws {
        let property = TestProperty {
            HostHeader("127.0.0.1", port: "8080")

            HeaderGroup {
                CacheHeader()
                    .public(true)

                CustomHeader(name: "xxx-api-key", value: "password")
            }

            AcceptHeader(.jpeg)
            OriginHeader("google.com")
        }

        let resolved = try await resolve(property)

        XCTAssertEqual(resolved.request.headers["Host"], ["127.0.0.1:8080"])
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
        XCTAssertEqual(resolved.request.headers["xxx-api-key"], ["password"])
        XCTAssertEqual(resolved.request.headers["Accept"], ["image/jpeg"])
        XCTAssertEqual(resolved.request.headers["Origin"], ["google.com"])
    }

    func testHeaders_whenInvalidGroup() async throws {
        // Given
        let property = TestProperty {
            BaseURL("127.0.0.1")
            HeaderGroup {
                Query(name: "api_key", value: "password")
            }
        }

        // When
        let resolved = try await resolve(property)

        // Then
        XCTAssertEqual(resolved.request.url, "https://127.0.0.1")
    }
}
