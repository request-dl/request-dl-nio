/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct QueryGroupTests {

    @Test
    func groupOfQueries() async throws {
        // Given
        let property = QueryGroup {
            Query(name: "number", value: 123)
            Query(name: "page", value: 1)
        }

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            property
        })

        // Then
        #expect(
            resolved.request.url,
            """
            https://127.0.0.1?\
            number=123&\
            page=1
            """
        )
    }

    @Test
    func groupOfQueriesIgnoringOtherTypes() async throws {
        // Given
        let property = QueryGroup {
            Query(name: "number", value: 123)
            Query(name: "page", value: 1)
            CustomHeader(name: "api_key", value: "password")
        }

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            property
        })

        // Then
        #expect(
            resolved.request.url,
            """
            https://127.0.0.1?\
            number=123&\
            page=1
            """
        )

        #expect(resolved.request.headers["api_key"] == nil)
    }

    @Test
    func queries_whenInitWithDictionary_shouldBeValid() async throws {
        // Given
        let queries = [
            "number": 123,
            "page": 1
        ]

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            QueryGroup(queries)
        })

        let queryItems = URL(string: resolved.request.url)
            .flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: true)
            }
            .flatMap(\.queryItems) ?? []

        // Then
        #expect(queryItems.count == 2)
        #expect(queryItems.contains(
            URLQueryItem(
                name: "number",
                value: "123"
            )
        ))
        #expect(queryItems.contains(
            URLQueryItem(
                name: "page",
                value: "1"
            )
        ))
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = QueryGroup {}

        // Then
        try await assertNever(property.body)
    }
}
