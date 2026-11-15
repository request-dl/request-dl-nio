//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(Darwin)

struct RequestConfigurationURLRequestTests {

    @Test
    func buildURLRequest_whenNothingSet_usesURLAndDefaultsToGET() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"

        // When
        let request = try await configuration.buildURLRequest()

        // Then
        #expect(request.url?.absoluteString == "https://example.com")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
    }

    @Test
    func buildURLRequest_whenMethodSet_usesIt() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.method = "POST"

        // When
        let request = try await configuration.buildURLRequest()

        // Then
        #expect(request.httpMethod == "POST")
    }

    @Test
    func buildURLRequest_whenHeadersSet_mapsEachPair() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.headers.set(name: "Content-Type", value: "application/json")
        configuration.headers.set(name: "Accept", value: "text/html")

        // When
        let request = try await configuration.buildURLRequest()

        // Then
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/html")
    }

    @Test
    func buildURLRequest_whenBodySet_buffersEveryChunkIntoHTTPBody() async throws {
        // Given
        let verbatim = "Hello, URLSession!"

        let resolved = try await resolve(
            TestProperty {
                Payload(verbatim: verbatim)
            }
        )

        // When
        let request = try await resolved.requestConfiguration.buildURLRequest()

        // Then
        #expect(request.httpBody.map { String(decoding: $0, as: UTF8.self) } == verbatim)
    }

    @Test
    func buildURLRequest_whenURLIsMalformed_throwsInvalidRequestURLError() async throws {
        // Given: no `BaseURL`, so `url` is empty, which `Foundation.URL(string:)` rejects.
        // Mirrors `BaseURL`'s own documented warning: omitting it is a real, reachable mistake,
        // not a hypothetical one.
        let configuration = RequestConfiguration()

        // When
        do {
            _ = try await configuration.buildURLRequest()
            Issue.record("Not expecting success")
        } catch let error as InvalidRequestURLError {
            // Then
            #expect(error.url == configuration.url)
        }
    }

    // MARK: - Header validation

    /// `.nio` rejects these in AsyncHTTPClient; `URLSession` would send them: `X-A: injected` as
    /// the line `X-A: injected: v`, a NUL as a NUL.
    @Test
    func buildURLRequest_whenHeaderNameIsNotAToken_throws() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.headers.set(name: "X-A: injected", value: "v")

        // When / Then
        await #expect(throws: (any Error).self) {
            _ = try await configuration.buildURLRequest()
        }
    }

    @Test
    func buildURLRequest_whenHeaderValueHasAControlCharacter_throws() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.headers.set(name: "X-A", value: "a\u{0000}b")

        // When / Then
        await #expect(throws: (any Error).self) {
            _ = try await configuration.buildURLRequest()
        }
    }

    @Test
    func buildURLRequestWithoutBody_whenHeaderIsInvalid_throws() throws {
        // Given: the path the streamed uploads, downloads and `DataTask` take.
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.headers.set(name: "X-A", value: "a\u{007F}b")

        // When / Then
        #expect(throws: (any Error).self) {
            _ = try configuration.buildURLRequestWithoutBody()
        }
    }

    /// The other half of the rule above: what `.nio` sends must not become an error here.
    @Test(arguments: ["José", "日本語", "a\u{0085}b", "a\u{2028}b", "tab\tseparated", ""])
    func buildURLRequest_whenHeaderValueIsLegitimate_keepsIt(value: String) async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.headers.set(name: "X-Custom-Header_1", value: value)

        // When
        let request = try await configuration.buildURLRequest()

        // Then
        #expect(request.value(forHTTPHeaderField: "X-Custom-Header_1") != nil)
    }
}

#endif
