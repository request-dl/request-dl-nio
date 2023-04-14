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
            BaseURL("127.0.0.1")
            property
        })

        // Then
        XCTAssertEqual(request.url, "https://127.0.0.1?number=123")
    }

    func testMultipleQueries() async throws {
        // Given
        let property = TestProperty {
            BaseURL("127.0.0.1")
            Query(123, forKey: "number")
            Query(1, forKey: "page")
            Query("password", forKey: "api_key")
            Query([9, "nine"] as [Any], forKey: "array")
        }

        // When
        let (_, request) = try await resolve(property)

        // Then
        XCTAssertEqual(
            request.url,
            """
            https://127.0.0.1?\
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
