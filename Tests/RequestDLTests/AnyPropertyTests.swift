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
            BaseURL("localhost")
            AnyProperty(property)
        })

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://localhost?number=123")
    }

    func testNeverBody() async throws {
        // Given
        let property = AnyProperty(EmptyProperty())

        // Then
        try await assertNever(property.body)
    }
}
