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
    func pathWithEmbeddedQuery() async throws {
        // Given
        let host = "google.com"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL(host)
                Path("api/v1/search?item=1&item=2")
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://\(host)/api/v1/search?item=1&item=2"
        )
    }

    /// Same contract as `FlexibleURL`: an embedded query is already percent encoded, and
    /// `RequestConfiguration.url` joins it as-is, so decoding it on the way in would turn `%26`
    /// back into a live `&` and split one parameter into two.
    @Test
    func pathWithEmbeddedQueryKeepsPercentEscapedDelimitersEscaped() async throws {
        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                Path("search?q=a%26b&n=1%2B1")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://google.com/search?q=a%26b&n=1%2B1")
    }

    @Test
    func pathWithEmbeddedQueryCombinedWithExplicitQuery() async throws {
        // Given
        let host = "google.com"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL(host)
                Path("api/v1/search?item=1&item=2")
                Query(name: "query", value: "123")
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.url == "https://\(host)/api/v1/search?item=1&item=2&query=123"
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = Path("")

        // Then
        try await assertNever(property.body)
    }

    // MARK: - Encoding

    @Test(arguments: [
        ("a b", "a%20b"),
        ("caf\u{E9}", "caf%C3%A9"),
        ("a%2Fb", "a%2Fb"),
        ("100%25", "100%25"),
        ("100%", "100%25"),
        ("50%OFF", "50%25OFF"),
        ("%C3%A9", "%C3%A9"),
        ("a#b", "a%23b"),
    ])
    func path_givesTheFormThatGoesOnTheWire(_ path: String, _ expected: String) async throws {
        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("example.com")
                Path(path)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com/\(expected)")
    }

    @Test
    func path_withAnEscapedSlash_staysOneSegment() async throws {
        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("example.com")
                Path("files")
                Path("a%2Fb")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com/files/a%2Fb")
    }
}
