/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersRefererTests: XCTestCase {

    func testReferer() async throws {
        let property = TestProperty(Headers.Referer("https://www.example.com/"))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.example.com/")
    }

    func testRefererWithHTML() async throws {
        let property = TestProperty(Headers.Referer("https://www.example.com/page1.html"))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.example.com/page1.html")
    }

    func testRefererWithPathAndQuery() async throws {
        let property = TestProperty(Headers.Referer("https://www.google.com/search?q=apple"))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.google.com/search?q=apple")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Referer("apple.com")

        // Then
        try await assertNever(property.body)
    }
}