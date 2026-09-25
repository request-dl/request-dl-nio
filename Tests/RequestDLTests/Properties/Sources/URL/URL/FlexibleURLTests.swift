//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct FlexibleURLTests {

    @Test func completeURL() async throws {
        // Given
        let endpointString = "https://api.example.com/v1/users"

        // When
        let resolved = try await resolve(FlexibleURL(endpointString))

        // Then
        #expect(resolved.requestConfiguration.url == endpointString)
    }

    @Test func completeURLWithQuery() async throws {
        // Given
        let endpointString = "https://api.example.com/v1/users?status=active&page=1"

        // When
        let resolved = try await resolve(FlexibleURL(endpointString))

        // Then
        #expect(resolved.requestConfiguration.url == endpointString)
    }

    /// `RequestConfiguration.url` joins query items as-is, expecting them already percent
    /// encoded. Reading them back decoded (`URLComponents.queryItems`) turned an escaped
    /// delimiter into a live one: `%26` split one parameter into two, `%3D` added a second `=`,
    /// and `%2B` became a `+` a server reads as a space.
    @Test(
        arguments: [
            "https://api.example.com/search?q=a%26b",
            "https://api.example.com/search?q=1%2B1&lang=en",
            "https://api.example.com/search?q=a%3Db",
        ]
    )
    func completeURLKeepsPercentEscapedDelimitersEscaped(_ endpointString: String) async throws {
        // When
        let resolved = try await resolve(FlexibleURL(endpointString))

        // Then
        #expect(resolved.requestConfiguration.url == endpointString)
    }

    @Test func relativeURLKeepsPercentEscapedDelimitersEscaped() async throws {
        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.example.com")
                FlexibleURL("/search?q=a%26b")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://api.example.com/search?q=a%26b")
    }

    @Test func completeURLWithPort() async throws {
        // Given
        let endpointString = "http://localhost:8080/api/debug"

        // When
        let resolved = try await resolve(FlexibleURL(endpointString))

        // Then
        #expect(resolved.requestConfiguration.url == endpointString)
    }

    @Test func relativePath() async throws {
        // Given
        let endpointPath = "/v2/data"
        let expectedUrl = "https://api.service.com/v2/data"  // BaseURL defaults to https

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                FlexibleURL(endpointPath)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func relativePathWithoutLeadingSlash() async throws {
        // Given
        let endpointPath = "v2/data"
        let expectedUrl = "https://api.service.com/v2/data"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                FlexibleURL(endpointPath)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func queryParametersOnly() async throws {
        // Given
        let queryParamString = "?q=foo&limit=10"
        let expectedUrl = "https://api.service.com/search?q=foo&limit=10"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                Path("search")
                FlexibleURL(queryParamString)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func relativePathWithTrailingSlash() async throws {
        // Given
        let endpointPath = "/folders/"
        let expectedUrl = "https://api.service.com/folders/"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                FlexibleURL(endpointPath)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func relativePathWithTrailingSlashFollowedByAnotherPath() async throws {
        // Given
        let endpointPath = "/folders/"
        let expectedUrl = "https://api.service.com/folders/item_id"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                FlexibleURL(endpointPath)
                Path("item_id")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    /// Regression coverage: classification used to search the *entire* normalized string for
    /// `"://"`, including the query, so an ordinary relative path whose query value happens to
    /// contain it (a redirect URL, say) was misread as a complete URL. Once parsed, that string
    /// has no `host`, so `baseURL` stayed untouched, but the path/query still appended with
    /// `fromStart: true` (the complete-URL branch's behavior) instead of `fromStart: false`,
    /// prepending "search" ahead of the existing "v1" path instead of after it.
    @Test func relativePathWithQueryValueContainingSchemeSeparator_appendsAfterExistingPath() async throws {
        // Given
        let endpointPath = "/search?redirect=http://evil.example.com"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                Path("v1")
                FlexibleURL(endpointPath)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.baseURL == "https://api.service.com")
        #expect(resolved.requestConfiguration.pathComponents.joinedAsPath() == "v1/search")
    }

    @Test func relativePathAppendedToExistingPath() async throws {
        // Given
        let endpointPath = "resource"
        let expectedUrl = "https://api.service.com/api/v1/resource"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                Path("api/v1")
                FlexibleURL(endpointPath)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func completeURLWithRelativePathOverridesBaseURL() async throws {
        // Given
        let completeFlexibleURL = "https://different-api.com/v3/status"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("should-be-overridden.com")
                FlexibleURL(completeFlexibleURL)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == completeFlexibleURL)
    }

    @Test func completeURLWithPathPrependsToExistingPath() async throws {
        // Given
        let completeFlexibleURLWithPrependPath = "https://api.service.com/new/endpoint"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                Path("old")
                FlexibleURL(completeFlexibleURLWithPrependPath)
            }
        )

        // Then
        // The path from the complete URL ("new/endpoint") should prepend to the existing path ("old").
        // Result should be the base URL from the complete URL plus the prepended path.
        #expect(resolved.requestConfiguration.url == "https://api.service.com/new/endpoint/old")
    }

    @Test func endpointWithSpacesTrimmed() async throws {
        // Given
        let endpointPath = " / spaced/path/ "
        let expectedUrl = "https://api.service.com/spaced/path/"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                FlexibleURL(endpointPath)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func invalidURLStringThrowsError() async throws {
        // Given
        let invalidFlexibleURLString = "not a valid url at all!"
        let expectedUrl = "/not a valid url at all!"

        // When
        let resolved = try await resolve(FlexibleURL(invalidFlexibleURLString))

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func endpointWithQueryAppendsToExistingQuery() async throws {
        // Given
        let endpointQueryString = "?added=by_endpoint&flag=true"
        let expectedUrl = "https://api.service.com?initial=param&added=by_endpoint&flag=true"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                Query(name: "initial", value: "param")
                FlexibleURL(endpointQueryString)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func completeURLWithQueryOverridesBaseURLAndAppendsQueries() async throws {
        // Given
        let completeFlexibleURLWithQuery = "https://new-api.com/v2/items?new_param=42"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("should-be-overridden.com")
                Query(name: "old_query", value: "value")
                FlexibleURL(completeFlexibleURLWithQuery)
            }
        )

        // Then
        // BaseURL is overridden. Existing query is appended *after* the query from the complete URL.
        // Result: New base URL + complete endpoint path + complete endpoint query + existing query.
        #expect(resolved.requestConfiguration.url == "https://new-api.com/v2/items?new_param=42&old_query=value")
    }

    @Test func neverBody() async throws {
        // Given
        let property = FlexibleURL("/some/path")

        // Then
        try await assertNever(property.body)
    }

    @Test func completeURLWithUnparseableHostThrowsInvalidURL() async throws {
        // Given
        let unparseableURL = "http://a b.com/x"
        var thrownError: FlexibleURLError?

        // When
        do {
            _ = try await resolve(FlexibleURL(unparseableURL))
        } catch let error as FlexibleURLError {
            thrownError = error
        }

        // Then
        if case .invalidURL = thrownError?.context {
            // Expected.
        } else {
            Issue.record("Expected .invalidURL, got \(String(describing: thrownError?.context))")
        }
        #expect(thrownError?.url == unparseableURL)
    }

    @Test func completeURLWithEmptyHostThrowsInvalidHost() async throws {
        // Given
        let emptyHostURL = "https:///path"
        var thrownError: FlexibleURLError?

        // When
        do {
            _ = try await resolve(FlexibleURL(emptyHostURL))
        } catch let error as FlexibleURLError {
            thrownError = error
        }

        // Then
        if case .invalidHost = thrownError?.context {
            // Expected.
        } else {
            Issue.record("Expected .invalidHost, got \(String(describing: thrownError?.context))")
        }
        #expect(thrownError?.url == emptyHostURL)
    }

    @Test func rootPathResolvesWithoutTrailingSlash() async throws {
        // Given
        let rootPath = "/"
        // A path made only of slashes is trimmed away entirely by `joinedAsPath()`, so the
        // final URL carries no path suffix even though `FlexibleURLNode` internally records a
        // single "/" path component for it.
        let expectedUrl = "https://api.service.com"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("api.service.com")
                FlexibleURL(rootPath)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }
}
