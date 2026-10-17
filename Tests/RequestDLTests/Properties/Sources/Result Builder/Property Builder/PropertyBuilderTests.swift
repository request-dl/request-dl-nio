//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct PropertyBuilderTests {

    @Test
    @available(*, deprecated)
    func singleBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            CacheHeader()
                .public(true)
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        #expect(property is CacheHeader)
        #expect(resolved.requestConfiguration.headers["Cache-Control"] == ["public"])
    }

    #if !os(Linux)
    @Test
    @available(*, deprecated)
    func limitedNotAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 99, macOS 99, watchOS 99, tvOS 99, visionOS 99, *) {
                CacheHeader()
                    .public(true)
            }
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        #expect(property is _OptionalContent<CacheHeader>)
        #expect(resolved.requestConfiguration.headers.isEmpty)
    }
    #endif

    @Test
    @available(*, deprecated)
    func limitedAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 14, macOS 12, watchOS 7, tvOS 14, *) {
                CacheHeader()
                    .public(true)
            }
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        #expect(property is _OptionalContent<CacheHeader>)
        #expect(resolved.requestConfiguration.headers["Cache-Control"] == ["public"])
    }
}
