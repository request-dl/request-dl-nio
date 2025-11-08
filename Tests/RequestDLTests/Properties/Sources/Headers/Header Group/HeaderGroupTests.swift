/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct HeaderGroupTests {

    @Test
    func headerGroupWithEmptyValue() async throws {
        let property = TestProperty(HeaderGroup {})
        let resolved = try await resolve(property)
        #expect(resolved.request.headers.isEmpty)
    }

    @Test
    func headerGroupWithDictionary() async throws {
        let property = TestProperty(HeaderGroup([
            "Content-Type": "application/json",
            "Accept": "text/html",
            "Origin": "127.0.0.1:8080",
            "xxx-api-key": "password"
        ]))

        let resolved = try await resolve(property)

        #expect(
            resolved.request.headers["Content-Type"],
            ["application/json"]
        )

        #expect(
            resolved.request.headers["Accept"],
            ["text/html"]
        )

        #expect(
            resolved.request.headers["Origin"],
            ["127.0.0.1:8080"]
        )

        #expect(
            resolved.request.headers["xxx-api-key"],
            ["password"]
        )
    }

    @Test
    func headerGroupWithMultipleHeaders() async throws {
        let property = TestProperty(HeaderGroup {
            CacheHeader()
                .public(true)
            AcceptHeader(.json)
            OriginHeader("127.0.0.1:8080")
            CustomHeader(name: "xxx-api-key", value: "password")
        })

        let resolved = try await resolve(property)

        #expect(
            resolved.request.headers["Cache-Control"],
            ["public"]
        )

        #expect(
            resolved.request.headers["Accept"],
            ["application/json"]
        )

        #expect(
            resolved.request.headers["Origin"],
            ["127.0.0.1:8080"]
        )

        #expect(
            resolved.request.headers["xxx-api-key"],
            ["password"]
        )
    }

    @Test
    func group_whenSameHeaderWithAddingStrategy() async throws {
        // Given
        let contentTypes: [ContentType] = [
            .json,
            .pdf,
            .gif,
            .html
        ]

        // When
        let resolved = try await resolve(TestProperty {
            HeaderGroup {
                AcceptHeader(.json)
                AcceptHeader(.pdf)
                AcceptHeader(.gif)
                AcceptHeader(.html)
            }
        })

        // Then
        #expect(
            resolved.request.headers["Accept"],
            contentTypes.map { String($0) }
        )
    }

    @Test
    func group_whenSameHeaderWithSettingStrategy() async throws {
        // Given
        let contentTypes: [ContentType] = [
            .json,
            .pdf,
            .gif,
            .html
        ]

        // When
        let resolved = try await resolve(TestProperty {
            HeaderGroup {
                AcceptHeader(.json)
                AcceptHeader(.pdf)
                AcceptHeader(.gif)
                AcceptHeader(.html)
            }
            .headerStrategy(.setting)
        })

        // Then
        #expect(
            resolved.request.headers["Accept"],
            contentTypes.last.map { [String($0)] } ?? []
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = HeaderGroup([:])

        // Then
        try await assertNever(property.body)
    }
}
