/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct PathTests {

    @Test
    func singlePath() async throws {
        // Given
        let path = "api"
        let host = "google.com"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL(host)
            Path(path)
        })

        // Then
        #expect(
            resolved.request.url,
            "https://\(host)/\(path)"
        )
    }

    @Test
    func path_whenInitWithLosslessValue() async throws {
        // Given
        let host = "google.com"
        let path = 123

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL(host)
            Path(path)
        })

        // Then
        #expect(
            resolved.request.url,
            "https://\(host)/\(path)"
        )
    }

    @Test
    func singleInstanceWithMultiplePath() async throws {
        // Given
        let path = "api/v1/users/10/detail"
        let host = "google.com"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL(host)
            Path(path)
        })

        // Then
        #expect(
            resolved.request.url,
            "https://\(host)/\(path)"
        )
    }

    @Test
    func multiplePath() async throws {
        // Given
        let path1 = "api"
        let path2 = "v1/"
        let path3 = "/users/10/detail"
        let host = "google.com"
        let characterSetRule = CharacterSet(charactersIn: "/")

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL(host)
            Path(path1)
            Path(path2)
            Path(path3)
        })

        // Then
        let expectedPath2 = path2.trimmingCharacters(in: characterSetRule)
        let expectedPath3 = path3.trimmingCharacters(in: characterSetRule)

        #expect(
            resolved.request.url,
            "https://\(host)/\(path1)/\(expectedPath2)/\(expectedPath3)"
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = Path("")

        // Then
        try await assertNever(property.body)
    }
}
