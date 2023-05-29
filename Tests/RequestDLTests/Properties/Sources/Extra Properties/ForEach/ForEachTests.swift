/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ForEachTests: XCTestCase {

    struct Value: Identifiable {
        let id: String
    }

    func testForEach_whenIDByIdentifiable_shouldBeValid() async throws {
        // Given
        let paths = ["api", "v1", "users"].map {
            Value(id: $0)
        }

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            PropertyForEach(paths) { path in
                Path(path.id)
            }
        })

        // Then
        XCTAssertEqual(
            resolved.request.url,
            "https://127.0.0.1/api/v1/users"
        )
    }

    func testForEach_whenIDBySelf_shouldBeValid() async throws {
        // Given
        let paths = ["api", "v1", "users"]

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            PropertyForEach(paths, id: \.self) { path in
                Path(path)
            }
        })

        // Then
        XCTAssertEqual(
            resolved.request.url,
            "https://127.0.0.1/api/v1/users"
        )
    }

    func testForEach_whenRange_shouldBeValid() async throws {
        // Given
        let range = 0 ..< 3

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            PropertyForEach(range) { index in
                Path("\(index)")
            }
        })

        // Then
        XCTAssertEqual(
            resolved.request.url,
            "https://127.0.0.1/\(range.map { "\($0)" }.joined(separator: "/"))"
        )
    }

    func testForEach_whenClosedRange_shouldBeValid() async throws {
        // Given
        let range = 0 ... 3

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("127.0.0.1")
            PropertyForEach(range) { index in
                Path("\(index)")
            }
        })

        // Then
        XCTAssertEqual(
            resolved.request.url,
            "https://127.0.0.1/\(range.map { "\($0)" }.joined(separator: "/"))"
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = PropertyForEach([Int](), id: \.self) { _ in
            EmptyProperty()
        }

        // Then
        try await assertNever(property.body)
    }
}
