/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class QueryTests: XCTestCase {

    func testSingleQuery() async throws {
        // Given
        let property = Query(123, forKey: "number")

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("localhost")
            property
        })

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://localhost?number=123")
    }

    func testMultipleQueries() async throws {
        // Given
        let property = TestProperty {
            BaseURL("localhost")
            Query(123, forKey: "number")
            Query(1, forKey: "page")
            Query("password", forKey: "api_key")
            Query([9, "nine"], forKey: "array")
        }

        // When
        let (_, request) = try await resolve(property)

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            """
            https://localhost?\
            number=123&\
            page=1&\
            api_key=password&\
            array=%5B9,%20%22nine%22%5D
            """
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = Query(123, forKey: "key")

        // Then
        try await assertNever(property.body)
    }
}
