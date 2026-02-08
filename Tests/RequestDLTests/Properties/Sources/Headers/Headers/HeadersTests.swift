/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct HeadersTests {

    @Test
    func headers_whenMultipleHeadersWithoutGroup() async throws {
        let property = TestProperty {
            CacheHeader()
                .public(true)
            AcceptHeader(.json)
            OriginHeader("127.0.0.1:8080")
            CustomHeader(name: "xxx-api-key", value: "password")
        }

        let resolved = try await resolve(property)

        #expect(resolved.requestConfiguration.headers["Cache-Control"] == ["public"])
        #expect(resolved.requestConfiguration.headers["Accept"] == ["application/json"])
        #expect(resolved.requestConfiguration.headers["Origin"] == ["127.0.0.1:8080"])
        #expect(resolved.requestConfiguration.headers["xxx-api-key"] == ["password"])
    }

    @Test
    func headers_whenSameHeaderSpecifyWithSettingStrategy() async throws {
        let property = TestProperty {
            CacheHeader()
                .public(true)

            CacheHeader()
                .proxyRevalidate()

            AcceptHeader(.jpeg)
            CustomHeader(name: "xxx-api-key", value: "password")
            CustomHeader(name: "xxx-api-key", value: "password123")
        }
        .headerStrategy(.setting)

        let resolved = try await resolve(property)

        #expect(resolved.requestConfiguration.headers["Cache-Control"] == ["proxy-revalidate"])
        #expect(resolved.requestConfiguration.headers["Accept"] == ["image/jpeg"])
        #expect(resolved.requestConfiguration.headers["xxx-api-key"] == ["password123"])
    }

    @Test
    func headers_whenSameHeaderWithGroupWithSettingStrategy() async throws {
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
        .headerStrategy(.setting)

        let resolved = try await resolve(property)

        #expect(resolved.requestConfiguration.headers["Cache-Control"] == ["proxy-revalidate"])
        #expect(resolved.requestConfiguration.headers["Accept"] == ["image/jpeg"])
        #expect(resolved.requestConfiguration.headers["xxx-api-key"] == ["password123"])
    }

    @Test
    func headers_whenSameHeaderSpecifyWithAddingStrategy() async throws {
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

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(
            resolved.requestConfiguration.headers["Cache-Control"] == ["public,proxy-revalidate"]
        )

        #expect(resolved.requestConfiguration.headers["Accept"] == ["image/jpeg"])

        #expect(
            resolved.requestConfiguration.headers["xxx-api-key"] == ["password", "password123"]
        )
    }

    @Test
    func headers_whenSameHeaderWithGroupWithAddingStrategy() async throws {
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

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(
            resolved.requestConfiguration.headers["Cache-Control"] == ["public,proxy-revalidate"]
        )

        #expect(resolved.requestConfiguration.headers["Accept"] == ["image/jpeg"])

        #expect(
            resolved.requestConfiguration.headers["xxx-api-key"] == ["password", "password123"]
        )
    }

    @Test
    func headers_whenCombinedHeadersWithGroup() async throws {
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

        #expect(resolved.requestConfiguration.headers["Host"] == ["127.0.0.1:8080"])
        #expect(resolved.requestConfiguration.headers["Cache-Control"] == ["public"])
        #expect(resolved.requestConfiguration.headers["xxx-api-key"] == ["password"])
        #expect(resolved.requestConfiguration.headers["Accept"] == ["image/jpeg"])
        #expect(resolved.requestConfiguration.headers["Origin"] == ["google.com"])
    }

    @Test
    func headers_whenInvalidGroup() async throws {
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
        #expect(resolved.requestConfiguration.url == "https://127.0.0.1")
    }
}
