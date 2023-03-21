/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersContentLengthTests: XCTestCase {

    func testContentLength() async throws {
        let property = TestProperty(Headers.ContentLength(1_000_000))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Length"), "1000000")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.ContentLength(1_000)

        // Then
        try await assertNever(property.body)
    }
}
