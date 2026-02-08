/*
 See LICENSE for this package's licensing information.
*/

import Foundation
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
        let expectedUrl = "https://api.service.com/v2/data" // BaseURL defaults to https

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("api.service.com")
            FlexibleURL(endpointPath)
        })

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func relativePathWithoutLeadingSlash() async throws {
        // Given
        let endpointPath = "v2/data"
        let expectedUrl = "https://api.service.com/v2/data"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("api.service.com")
            FlexibleURL(endpointPath)
        })

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func queryParametersOnly() async throws {
        // Given
        let queryParamString = "?q=foo&limit=10"
        let expectedUrl = "https://api.service.com/search?q=foo&limit=10"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("api.service.com")
            Path("search")
            FlexibleURL(queryParamString)
        })

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func relativePathWithTrailingSlash() async throws {
        // Given
        let endpointPath = "/folders/"
        let expectedUrl = "https://api.service.com/folders/"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("api.service.com")
            FlexibleURL(endpointPath)
        })

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func relativePathWithTrailingSlashFollowedByAnotherPath() async throws {
        // Given
        let endpointPath = "/folders/"
        let expectedUrl = "https://api.service.com/folders/item_id"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("api.service.com")
            FlexibleURL(endpointPath)
            Path("item_id")
        })

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func relativePathAppendedToExistingPath() async throws {
        // Given
        let endpointPath = "resource"
        let expectedUrl = "https://api.service.com/api/v1/resource"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("api.service.com")
            Path("api/v1")
            FlexibleURL(endpointPath)
        })

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func completeURLWithRelativePathOverridesBaseURL() async throws {
        // Given
        let completeFlexibleURL = "https://different-api.com/v3/status"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("should-be-overridden.com")
            FlexibleURL(completeFlexibleURL)
        })

        // Then
        #expect(resolved.requestConfiguration.url == completeFlexibleURL)
    }

    @Test func completeURLWithPathPrependsToExistingPath() async throws {
        // Given
        let completeFlexibleURLWithPrependPath = "https://api.service.com/new/endpoint"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("api.service.com")
            Path("old")
            FlexibleURL(completeFlexibleURLWithPrependPath)
        })

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
        let resolved = try await resolve(TestProperty {
            BaseURL("api.service.com")
            FlexibleURL(endpointPath)
        })

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
        let resolved = try await resolve(TestProperty {
            BaseURL("api.service.com")
            Query(name: "initial", value: "param")
            FlexibleURL(endpointQueryString)
        })

        // Then
        #expect(resolved.requestConfiguration.url == expectedUrl)
    }

    @Test func completeURLWithQueryOverridesBaseURLAndAppendsQueries() async throws {
        // Given
        let completeFlexibleURLWithQuery = "https://new-api.com/v2/items?new_param=42"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL("should-be-overridden.com")
            Query(name: "old_query", value: "value")
            FlexibleURL(completeFlexibleURLWithQuery)
        })

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
}
