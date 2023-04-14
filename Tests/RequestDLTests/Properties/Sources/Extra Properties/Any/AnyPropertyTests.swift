/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class AnyPropertyTests: XCTestCase {

    func testAnyPropertyErasingQuery() async throws {
        // Given
        let property = Query(123, forKey: "number")

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            AnyProperty(property)
        })

        // Then
        XCTAssertEqual(request.url, "https://127.0.0.1?number=123")
    }

    func testNeverBody() async throws {
        // Given
        let property = AnyProperty(EmptyProperty())

        // Then
        try await assertNever(property.body)
    }
}
