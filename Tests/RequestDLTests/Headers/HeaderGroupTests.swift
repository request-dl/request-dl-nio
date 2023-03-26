/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeaderGroupTests: XCTestCase {

    func testHeaderGroupWithEmptyValue() async throws {
        let property = TestProperty(HeaderGroup {})
        let (_, request) = try await resolve(property)
        XCTAssertTrue(request.allHTTPHeaderFields?.isEmpty ?? true)
    }

    func testHeaderGroupWithDictionary() async throws {
        let property = TestProperty(HeaderGroup([
            "Content-Type": "application/json",
            "Accept": "text/html",
            "Origin": "localhost:8080",
            "xxx-api-key": "password"
        ]))

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/html")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "localhost:8080")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password")
    }

    func testHeaderGroupWithMultipleHeaders() async throws {
        let property = TestProperty(HeaderGroup {
            Headers.ContentType(.javascript)
            Headers.Accept(.json)
            Headers.Origin("localhost:8080")
            Headers.Any("password", forKey: "xxx-api-key")
        })

        let (_, request) = try await resolve(property)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/javascript")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "localhost:8080")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xxx-api-key"), "password")
    }

    func testNeverBody() async throws {
        // Given
        let property = HeaderGroup([:])

        // Then
        try await assertNever(property.body)
    }
}
