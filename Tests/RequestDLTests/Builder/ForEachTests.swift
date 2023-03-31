/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ForEachTests: XCTestCase {

    func testForEach_whenIDBySelf_shouldBeValid() async throws {
        // Given
        let paths = ["api", "v1", "users"]

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("localhost")
            ForEach(paths, id: \.self) { path in
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
