/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ForEachTests {

    struct Value: Identifiable {
        let id: String
    }

    @Test
    func forEach_whenIDByIdentifiable_shouldBeValid() async throws {
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
        #expect(
            resolved.request.url == "https://127.0.0.1/api/v1/users"
        )
    }

    @Test
    func forEach_whenIDBySelf_shouldBeValid() async throws {
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
        #expect(
            resolved.request.url == "https://127.0.0.1/api/v1/users"
        )
    }

    @Test
    func forEach_whenRange_shouldBeValid() async throws {
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
        #expect(
            resolved.request.url == "https://127.0.0.1/\(range.map { "\($0)" }.joined(separator: "/"))"
        )
    }

    @Test
    func forEach_whenClosedRange_shouldBeValid() async throws {
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
        #expect(
            resolved.request.url == "https://127.0.0.1/\(range.map { "\($0)" }.joined(separator: "/"))"
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = PropertyForEach([Int](), id: \.self) { _ in
            EmptyProperty()
        }

        // Then
        try await assertNever(property.body)
    }
}
