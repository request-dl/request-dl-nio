/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct GroupTests {

    @Test
    func singleGroup() async throws {
        // Given
        let property = PropertyGroup {
            BaseURL("google.com")
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        #expect(resolved.request.url == "https://google.com")
    }

    @Test
    func multipleGroup() async throws {
        // Given
        let property = PropertyGroup {
            BaseURL("google.com")
            Path("api/v1")
            Query(name: "available_methods", value: "all")
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        #expect(
            resolved.request.url,
            "https://google.com/api/v1?available_methods=all"
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = PropertyGroup {}

        // Then
        try await assertNever(property.body)
    }
}
