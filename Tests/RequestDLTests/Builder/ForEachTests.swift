/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ForEachTests: XCTestCase {

    func testForEach() async {
        // Given
        let paths = ["api", "v1", "users"]

        // When
        let (_, request) = await resolve(TestProperty {
            BaseURL("localhost")
            ForEach(paths) { path in
                Path(path)
            }
        })

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://localhost/api/v1/users"
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = ForEach([Int]()) { _ in
            EmptyProperty()
        }

        // Then
        try await assertNever(property.body)
    }
}
