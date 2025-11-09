/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct EmptyPropertyTests {

    @Test
    func emptyBuilder() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            // swiftlint:disable redundant_discardable_let
            let _ = 1
            // swiftlint:enable redundant_discardable_let
        }

        // When
        _ = try await resolve(TestProperty(property))

        // Then
        #expect(property is EmptyProperty)
    }

    @Test
    func emptyExplicitBuilder() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            EmptyProperty()
        }

        // When
        _ = try await resolve(TestProperty(property))

        // Then
        #expect(property is EmptyProperty)
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = EmptyProperty()

        // Then
        try await assertNever(property.body)
    }
}
