/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class HeaderGroupTests: XCTestCase {

    func testHeaderGroupWithEmptyValue() async throws {
        let property = TestProperty(HeaderGroup {})
        let resolved = try await resolve(property)
        XCTAssertTrue(resolved.request.headers.isEmpty)
    }

    func testHeaderGroupWithDictionary() async throws {
        let property = TestProperty(HeaderGroup([
            "Content-Type": "application/json",
            "Accept": "text/html",
            "Origin": "127.0.0.1:8080",
            "xxx-api-key": "password"
        ]))

        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/json"]
        )

        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["text/html"]
        )

        XCTAssertEqual(
            resolved.request.headers["Origin"],
            ["127.0.0.1:8080"]
        )

        XCTAssertEqual(
            resolved.request.headers["xxx-api-key"],
            ["password"]
        )
    }

    func testHeaderGroupWithMultipleHeaders() async throws {
        let property = TestProperty(HeaderGroup {
            CacheHeader()
                .public(true)
            AcceptHeader(.json)
            OriginHeader("127.0.0.1:8080")
            CustomHeader(name: "xxx-api-key", value: "password")
        })

        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers["Cache-Control"],
            ["public"]
        )

        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["application/json"]
        )

        XCTAssertEqual(
            resolved.request.headers["Origin"],
            ["127.0.0.1:8080"]
        )

        XCTAssertEqual(
            resolved.request.headers["xxx-api-key"],
            ["password"]
        )
    }

    func testGroup_whenSameHeaderWithAddingStrategy() async throws {
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
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            contentTypes.map { String($0) }
        )
    }

    func testGroup_whenSameHeaderWithSettingStrategy() async throws {
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
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            contentTypes.last.map { [String($0)] } ?? []
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = HeaderGroup([:])

        // Then
        try await assertNever(property.body)
    }
}
