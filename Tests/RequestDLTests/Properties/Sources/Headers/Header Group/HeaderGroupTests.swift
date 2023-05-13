/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
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
            resolved.request.headers.getValue(forKey: "Content-Type"),
            "application/json"
        )

        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "text/html"
        )

        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Origin"),
            "127.0.0.1:8080"
        )

        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "xxx-api-key"),
            "password"
        )
    }

    func testHeaderGroupWithMultipleHeaders() async throws {
        let property = TestProperty(HeaderGroup {
            Headers.ContentType(.javascript)
            Headers.Accept(.json)
            Headers.Origin("127.0.0.1:8080")
            Headers.Any("password", forKey: "xxx-api-key")
        })

        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Content-Type"),
            "text/javascript"
        )

        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "application/json"
        )

        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Origin"),
            "127.0.0.1:8080"
        )

        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "xxx-api-key"),
            "password"
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = HeaderGroup([:])

        // Then
        try await assertNever(property.body)
    }
}
