//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.URLComponents
#endif

/// The parsed `"scheme://host[/path]"` shape shared by both sides of a `URLOverride` rule.
struct URLOverrideEndpoint: Sendable, Equatable {

    let scheme: String
    let host: String
    let pathComponents: [String]
}

extension URLOverrideEndpoint {

    /// Parses a user-supplied origin/destination string.
    ///
    /// A bare host (no `"scheme://"`) is rejected rather than defaulted, unlike ``BaseURL`` or
    /// ``FlexibleURL`` — with two strings per rule instead of one, an implicit scheme would make
    /// it ambiguous which side of the pair a validation failure came from.
    init(parsing url: String) throws {
        // `Character.isWhitespace` already covers newlines, so this is the whole of
        // `.whitespacesAndNewlines` without needing `Foundation.CharacterSet`.
        let normalized = url.trimming(where: \.isWhitespace)

        guard let parsedURL = URL(string: normalized),
            let components = URLComponents(url: parsedURL, resolvingAgainstBaseURL: false)
        else {
            throw URLOverrideError(context: .invalidURL, url: url)
        }

        guard let scheme = components.scheme, !scheme.isEmpty else {
            throw URLOverrideError(context: .missingScheme, url: url)
        }

        guard let host = components.host, !host.isEmpty else {
            throw URLOverrideError(context: .missingHost, url: url)
        }

        self.scheme = scheme
        self.host = host
        self.pathComponents = Array(
            components.path
                .split(separator: "/")
                .lazy
                .filter { !$0.isEmpty }
                .map(String.init)
        )
    }

    /// Parses an already-normalized `"scheme://host"` request base URL (see
    /// `RequestConfiguration.baseURL`/``BaseURL``) for matching against a rule's origin.
    ///
    /// Returns `nil` instead of throwing for an empty/malformed value (e.g. no ``BaseURL``
    /// declared) — this runs after the property tree has already fully resolved, past the point
    /// where a `Property` can still fail the build; an unmatched request should just pass through.
    init?(baseURL: String) {
        guard let separatorRange = baseURL.range(of: "://") else {
            return nil
        }

        let scheme = String(baseURL[..<separatorRange.lowerBound])
        let host = String(baseURL[separatorRange.upperBound...])

        guard !scheme.isEmpty, !host.isEmpty else {
            return nil
        }

        self.scheme = scheme
        self.host = host
        self.pathComponents = []
    }
}
