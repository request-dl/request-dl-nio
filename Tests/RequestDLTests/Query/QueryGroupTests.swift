/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class QueryGroupTests: XCTestCase {

    func testGroupOfQueries() async throws {
        // Given
        let property = QueryGroup {
            Query(123, forKey: "number")
            Query(1, forKey: "page")
        }

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("localhost")
            property
        })

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            """
            https://localhost?\
            number=123&\
            page=1
            """
        )
    }

    func testGroupOfQueriesIgnoringOtherTypes() async throws {
        // Given
        let property = QueryGroup {
            Query(123, forKey: "number")
            Query(1, forKey: "page")
            Headers.Any("password", forKey: "api_key")
        }

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("localhost")
            property
        })

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            """
            https://localhost?\
            number=123&\
            page=1
            """
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "api_key"))
    }

    func testQueries_whenInitWithDictionary_shouldBeValid() async throws {
        // Given
        let queries = [
            "number": 123,
            "page": 1
        ]

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("localhost")
            QueryGroup(queries)
        })

        let queryItems = request.url
            .flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: true)
            }
            .flatMap(\.queryItems) ?? []

        // Then
        XCTAssertEqual(queryItems.count, 2)
        XCTAssertTrue(queryItems.contains(
            URLQueryItem(
                name: "number",
                value: "123"
            )
        ))
        XCTAssertTrue(queryItems.contains(
            URLQueryItem(
                name: "page",
                value: "1"
            )
        ))
    }

    func testNeverBody() async throws {
        // Given
        let property = QueryGroup {}

        // Then
        try await assertNever(property.body)
    }
}
