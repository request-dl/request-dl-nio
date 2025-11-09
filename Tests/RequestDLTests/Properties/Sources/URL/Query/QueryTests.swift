/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct QueryTests {

    @Test
    func singleQuery() async throws {
        // Given
        let property = Query(name: "number", value: 123)

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            property
        })

        // Then
        #expect(resolved.request.url == "https://127.0.0.1?number=123")
    }

    @Test
    func multipleQueries() async throws {
        // Given
        let property = TestProperty {
            BaseURL("127.0.0.1")
            Query(name: "number", value: 123)
            Query(name: "page", value: 1)
            Query(name: "api_key", value: "password")
            Query(name: "array", value: [9, "nine"] as [Sendable])
        }

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(
            resolved.request.url == """
            https://127.0.0.1?\
            number=123&\
            page=1&\
            api_key=password&\
            array=9&\
            array=nine
            """
        )
    }

    @Test
    func query_withModifiedURLEncoder() async throws {
        // Given
        let urlEncoder = URLEncoder()
        urlEncoder.boolEncodingStrategy = .numeric
        urlEncoder.arrayEncodingStrategy = .accessMember

        let property = TestProperty {
            BaseURL("127.0.0.1")
            PropertyGroup {
                Query(name: "flag", value: true)
                Query(name: "array", value: [9, "nine"] as [Sendable])
            }
            .urlEncoder(urlEncoder)
        }

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(
            resolved.request.url == """
            https://127.0.0.1?\
            flag=1&\
            array.0=9&\
            array.1=nine
            """
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = Query(name: "key", value: 123)

        // Then
        try await assertNever(property.body)
    }
}
