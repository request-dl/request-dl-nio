//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.URLComponents
#endif

/// The parsed `"scheme://host[:port][/path]"` shape shared by both sides of a `URLOverride` rule.
struct URLOverrideEndpoint: Sendable, Equatable {

    let scheme: String
    let host: String
    /// `nil` when the endpoint carries no explicit port (matches/rewrites regardless of the
    /// other side's port). Kept distinct from `host` — unlike `URLComponents.host`, which never
    /// includes it — so a rule origin/destination declaring a non-default port doesn't silently
    /// match or rewrite to the wrong one. See `init(baseURL:)`.
    let port: Int?
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
        self.port = components.port
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
        // Neither `range(of:)` (a Foundation member this file has no import for) nor
        // `firstRange(of:)`/`contains(_:)` for a substring pattern (stdlib, but gated to
        // macOS 13/iOS 16 — newer than this package's macOS 12/iOS 15 minimum). A single
        // `Character` lookup plus `hasPrefix` has neither restriction.
        guard let colonIndex = baseURL.firstIndex(of: ":") else {
            return nil
        }

        let afterColon = baseURL.index(after: colonIndex)

        guard baseURL[afterColon...].hasPrefix("//") else {
            return nil
        }

        let scheme = String(baseURL[..<colonIndex])
        let hostAndPort = baseURL[baseURL.index(afterColon, offsetBy: 2)...]

        // `FlexibleURLNode.constructBaseURLString` appends `":\(port)"` after the host when one
        // was specified, so this reverses that: everything after the *last* colon, if it's a
        // run of digits, is the port; otherwise there's none to split off. Scanning from the end
        // (rather than the first colon) matters because a bracketed IPv6 host would otherwise
        // split on one of its own colons instead — this still can't tell an IPv6 host without a
        // port from one whose brackets got lost, but that ambiguity predates this initializer.
        let host: String
        let port: Int?

        if let lastColonIndex = hostAndPort.lastIndex(of: ":"),
            let parsedPort = Int(hostAndPort[hostAndPort.index(after: lastColonIndex)...]),
            !hostAndPort[hostAndPort.index(after: lastColonIndex)...].isEmpty
        {
            host = String(hostAndPort[..<lastColonIndex])
            port = parsedPort
        } else {
            host = String(hostAndPort)
            port = nil
        }

        guard !scheme.isEmpty, !host.isEmpty else {
            return nil
        }

        self.scheme = scheme
        self.host = host
        self.port = port
        self.pathComponents = []
    }
}
