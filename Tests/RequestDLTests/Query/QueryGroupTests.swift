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

    func testNeverBody() async throws {
        // Given
        let property = QueryGroup {}

        // Then
        try await assertNever(property.body)
    }
}
