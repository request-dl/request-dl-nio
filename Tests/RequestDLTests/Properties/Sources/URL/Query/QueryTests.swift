/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class QueryTests: XCTestCase {

    func testSingleQuery() async throws {
        // Given
        let property = Query(123, forKey: "number")

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            property
        })

        // Then
        XCTAssertEqual(resolved.request.url, "https://127.0.0.1?number=123")
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
        let resolved = try await resolve(property)

        // Then
        XCTAssertEqual(
            resolved.request.url,
            """
            https://127.0.0.1?\
            number=123&\
            page=1&\
            api_key=password&\
            array=9&\
            array=nine
            """
        )
    }

    func testQuery_withModifiedURLEncoder() async throws {
        // Given
        let urlEncoder = URLEncoder()
        urlEncoder.boolEncodingStrategy = .numeric
        urlEncoder.arrayEncodingStrategy = .accessMember

        let property = TestProperty {
            BaseURL("127.0.0.1")
            PropertyGroup {
                Query(true, forKey: "flag")
                Query([9, "nine"] as [Any], forKey: "array")
            }
            .urlEncoder(urlEncoder)
        }

        // When
        let resolved = try await resolve(property)

        // Then
        XCTAssertEqual(
            resolved.request.url,
            """
            https://127.0.0.1?\
            flag=1&\
            array.0=9&\
            array.1=nine
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
