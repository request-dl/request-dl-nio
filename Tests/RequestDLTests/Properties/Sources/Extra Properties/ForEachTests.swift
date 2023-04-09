/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ForEachTests: XCTestCase {

    struct Value: Identifiable {
        let id: String
    }

    func testForEach_whenIDByIdentifiable_shouldBeValid() async throws {
        // Given
        let paths = ["api", "v1", "users"].map {
            Value(id: $0)
        }

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL("localhost")
            ForEach(paths) { path in
                Path(path.id)
            }
        })

        // Then
        XCTAssertEqual(
            request.url,
            "https://localhost/api/v1/users"
        )
    }

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
            request.url,
            "https://localhost/api/v1/users"
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = ForEach([Int](), id: \.self) { _ in
            EmptyProperty()
        }

        // Then
        try await assertNever(property.body)
    }
}
