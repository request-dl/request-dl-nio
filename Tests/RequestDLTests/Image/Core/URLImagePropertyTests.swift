//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDL

#if canImport(UIKit) || canImport(AppKit)
struct URLImagePropertyTests {

    @Test
    func hostOnly() async throws {
        // Given
        let url = URL(string: "https://example.com")!

        // When
        let resolved = try await resolve(URLImageProperty(url: url))

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com")
    }

    @Test
    func httpScheme() async throws {
        // Given
        let url = URL(string: "http://example.com")!

        // When
        let resolved = try await resolve(URLImageProperty(url: url))

        // Then
        #expect(resolved.requestConfiguration.url == "http://example.com")
    }

    @Test
    func hostWithPort() async throws {
        // Given
        let url = URL(string: "https://example.com:8443/image.png")!

        // When
        let resolved = try await resolve(URLImageProperty(url: url))

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com:8443/image.png")
    }

    @Test
    func hostWithPath() async throws {
        // Given
        let url = URL(string: "https://example.com/assets/avatar.png")!

        // When
        let resolved = try await resolve(URLImageProperty(url: url))

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com/assets/avatar.png")
    }

    @Test
    func hostWithQuery() async throws {
        // Given
        let url = URL(string: "https://example.com/avatar?size=200&format=png")!

        // When
        let resolved = try await resolve(URLImageProperty(url: url))

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com/avatar?size=200&format=png")
    }

    @Test
    func queryValuesAreNotDoubleEncoded() async throws {
        // Given
        // RequestConfiguration.queries is documented as expecting values that are already
        // percent encoded. URLImageProperty must forward the URL's own encoding as-is instead
        // of encoding it a second time, or "%20" here would come out as "%2520".
        let url = URL(string: "https://example.com/avatar?name=John%20Doe")!

        // When
        let resolved = try await resolve(URLImageProperty(url: url))

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com/avatar?name=John%20Doe")
    }
}
#endif
