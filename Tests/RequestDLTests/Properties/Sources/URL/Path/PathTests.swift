//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#endif

struct PathTests {

    @Test
    func singlePath() async throws {
        // Given
        let path = "api"
        let host = "google.com"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL(host)
                Path(path)
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://\(host)/\(path)"
        )
    }

    @Test
    func path_whenInitWithLosslessValue() async throws {
        // Given
        let host = "google.com"
        let path = 123

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL(host)
                Path(path)
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://\(host)/\(path)"
        )
    }

    @Test
    func singleInstanceWithMultiplePath() async throws {
        // Given
        let path = "api/v1/users/10/detail"
        let host = "google.com"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL(host)
                Path(path)
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://\(host)/\(path)"
        )
    }

    @Test
    func multiplePath() async throws {
        // Given
        let path1 = "api"
        let path2 = "v1/"
        let path3 = "/users/10/detail"
        let host = "google.com"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL(host)
                Path(path1)
                Path(path2)
                Path(path3)
            }
        )

        // Then
        // `CharacterSet`/`trimmingCharacters(in:)` are not part of `FoundationEssentials`; the
        // package's own `trimming(where:)` trims the same "/" from both ends.
        let expectedPath2 = path2.trimming { $0 == "/" }
        let expectedPath3 = path3.trimming { $0 == "/" }

        #expect(
            resolved.requestConfiguration.url == "https://\(host)/\(path1)/\(expectedPath2)/\(expectedPath3)"
        )
    }

    @Test
    func multiplePathWithForwardSlash() async throws {
        // Given
        let path1 = "/api/"
        let path2 = "/v1/"
        let path3 = "/users/10/detail/"
        let host = "google.com"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL(host)
                Path(path1)
                Path(path2)
                Path(path3)
            }
        )

        // Then
        let expectedPath1 = path1.trimming { $0 == "/" }
        let expectedPath2 = path2.trimming { $0 == "/" }
        let expectedPath3 = path3.trimming { $0 == "/" }

        #expect(
            resolved.requestConfiguration.url == "https://\(host)/\(expectedPath1)/\(expectedPath2)/\(expectedPath3)/"
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
