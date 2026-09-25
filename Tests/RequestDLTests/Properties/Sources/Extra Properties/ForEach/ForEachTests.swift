//
// See LICENSE for this package's licensing information.
//

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
        let resolved = try await resolve(
            TestProperty {
                BaseURL("127.0.0.1")
                PropertyForEach(paths) { path in
                    Path(path.id)
                }
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://127.0.0.1/api/v1/users"
        )
    }

    @Test
    func forEach_whenIDBySelf_shouldBeValid() async throws {
        // Given
        let paths = ["api", "v1", "users"]

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("127.0.0.1")
                PropertyForEach(paths, id: \.self) { path in
                    Path(path)
                }
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://127.0.0.1/api/v1/users"
        )
    }

    @Test
    func forEach_whenRange_shouldBeValid() async throws {
        // Given
        let range = 0..<3

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("127.0.0.1")
                PropertyForEach(range) { index in
                    Path("\(index)")
                }
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://127.0.0.1/\(range.map { "\($0)" }.joined(separator: "/"))"
        )
    }

    @Test
    func forEach_whenClosedRange_shouldBeValid() async throws {
        // Given
        let range = 0...3

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("127.0.0.1")
                PropertyForEach(range) { index in
                    Path("\(index)")
                }
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://127.0.0.1/\(range.map { "\($0)" }.joined(separator: "/"))"
        )
    }

    /// Regression coverage: a `@StoredObject` declared inside a `PropertyForEach` element's own
    /// content used to be keyed by visit order alone, the same as any other sibling property --
    /// so reordering the same collection reassigned each element's stored state by its new
    /// position instead of keeping it with the data it actually belongs to.
    @Test
    func forEach_whenElementsReordered_storedObjectIdentityFollowsIDNotPosition() async throws {
        // Given
        final class Factory: Index, IndexFactory, @unchecked Sendable {

            static let producer = IndexProducer()

            init() {
                super.init(Self.producer)
            }
        }

        struct Element: Property {
            let label: String

            @StoredObject var factory = Factory()

            var body: some Property {
                Path("\(label)-\(factory.rawValue)")
            }
        }

        // When: the same three ids, resolved once in declared order and once reordered.
        let resolved1 = try await resolve(
            TestProperty {
                BaseURL("www.apple.com")
                PropertyForEach(["a", "b", "c"], id: \.self) { Element(label: $0) }
            }
        )

        let resolved2 = try await resolve(
            TestProperty {
                BaseURL("www.apple.com")
                PropertyForEach(["c", "a", "b"], id: \.self) { Element(label: $0) }
            }
        )

        // Then: exactly three `Factory` instances exist in total, and each id's own instance --
        // so each id's own `rawValue` -- travels with it regardless of position, instead of a
        // new one being minted per position or an unrelated id's state being reused instead.
        #expect(Factory.producer.index == 3)
        #expect(resolved1.requestConfiguration.url == "https://www.apple.com/a-0/b-1/c-2")
        #expect(resolved2.requestConfiguration.url == "https://www.apple.com/c-2/a-0/b-1")
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
