/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeaderGroupTests: XCTestCase {

    func testHeaderGroupWithEmptyValue() async throws {
        let property = TestProperty(HeaderGroup {})
        let (_, request) = try await resolve(property)
        XCTAssertTrue(request.headers.isEmpty)
    }

    func testHeaderGroupWithDictionary() async throws {
        let property = TestProperty(HeaderGroup([
            "Content-Type": "application/json",
            "Accept": "text/html",
            "Origin": "localhost:8080",
            "xxx-api-key": "password"
        ]))

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "application/json")
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "text/html")
        XCTAssertEqual(request.headers.getValue(forKey: "Origin"), "localhost:8080")
        XCTAssertEqual(request.headers.getValue(forKey: "xxx-api-key"), "password")
    }

    func testHeaderGroupWithMultipleHeaders() async throws {
        let property = TestProperty(HeaderGroup {
            Headers.ContentType(.javascript)
            Headers.Accept(.json)
            Headers.Origin("localhost:8080")
            Headers.Any("password", forKey: "xxx-api-key")
        })

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "text/javascript")
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "application/json")
        XCTAssertEqual(request.headers.getValue(forKey: "Origin"), "localhost:8080")
        XCTAssertEqual(request.headers.getValue(forKey: "xxx-api-key"), "password")
    }

    func testNeverBody() async throws {
        // Given
        let property = HeaderGroup([:])

        // Then
        try await assertNever(property.body)
    }
}
