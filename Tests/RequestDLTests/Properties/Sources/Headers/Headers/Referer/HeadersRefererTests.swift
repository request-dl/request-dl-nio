/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class HeadersRefererTests: XCTestCase {

    func testReferer() async throws {
        let property = TestProperty(Headers.Referer("https://www.example.com/"))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers.getValue(forKey: "Referer"), "https://www.example.com/")
    }

    func testRefererWithHTML() async throws {
        let property = TestProperty(Headers.Referer("https://www.example.com/page1.html"))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers.getValue(forKey: "Referer"), "https://www.example.com/page1.html")
    }

    func testRefererWithPathAndQuery() async throws {
        let property = TestProperty(Headers.Referer("https://www.google.com/search?q=apple"))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers.getValue(forKey: "Referer"), "https://www.google.com/search?q=apple")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Referer("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
