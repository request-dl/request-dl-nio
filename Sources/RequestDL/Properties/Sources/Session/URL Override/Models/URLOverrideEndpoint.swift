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
    /// `nil` when the endpoint carries no explicit port, which for matching means the scheme's
    /// default (see ``isSameOrigin(as:)``). Kept distinct from `host`, which like
    /// `URLComponents.host` never includes it, so a rule origin/destination declaring a
    /// non-default port doesn't silently match or rewrite to the wrong one. See `init(baseURL:)`.
    let port: Int?
    let pathComponents: [String]
}

extension URLOverrideEndpoint {

    /// Whether `self` and `other` name the same origin: the same scheme, host and port.
    ///
    /// Scheme and host are compared without regard to case, since neither is case sensitive
    /// (RFC 3986 §3.1, §3.2.2), and a bracketed IPv6 host is the same as the bare one. A port is
    /// compared as the port the connection would use: one left out is the scheme's default, so
    /// `https://example.com` and `https://example.com:443` are the same origin. A port that is not
    /// the default still tells two origins apart, and so does a scheme with no default port.
    func isSameOrigin(as other: URLOverrideEndpoint) -> Bool {
        normalizedScheme == other.normalizedScheme
            && normalizedHost == other.normalizedHost
            && effectivePort == other.effectivePort
    }

    private var normalizedScheme: String {
        scheme.lowercased()
    }

    private var normalizedHost: String {
        var host = self.host.lowercased()

        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }

        return host
    }

    private var effectivePort: Int? {
        port ?? Self.defaultPort(forScheme: normalizedScheme)
    }

    private static func defaultPort(forScheme scheme: String) -> Int? {
        switch scheme {
        case "http", "ws":
            return 80
        case "https", "wss":
            return 443
        default:
            return nil
        }
    }

    /// Parses a user-supplied origin/destination string.
    ///
    /// A bare host (no `"scheme://"`) is rejected rather than defaulted, unlike ``BaseURL`` or
    /// ``FlexibleURL``: with two strings per rule instead of one, an implicit scheme would make
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
    /// declared), since this runs after the property tree has fully resolved, past the point
    /// where a `Property` can still fail the build. An unmatched request should just pass through.
    init?(baseURL: String) {
        // Neither `range(of:)` (a Foundation member this file has no import for) nor
        // `firstRange(of:)`/`contains(_:)` for a substring pattern (stdlib, but gated to macOS
        // 13/iOS 16, newer than this package's macOS 12/iOS 15 minimum) can be used. A single
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

        // `FlexibleURLNode.constructBaseURLString` appends `":\(port)"` after the host when one was
        // specified, so this reverses that: everything after the *last* colon, if it's a run of
        // digits, is the port; otherwise there's none to split off. Scanning from the end (rather
        // than the first colon) matters because a bracketed IPv6 host would otherwise split on one
        // of its own colons. This still can't tell an IPv6 host without a port from one whose
        // brackets got lost.
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
