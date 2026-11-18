//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.URLComponents
#endif

extension Internals {

    /// The rules of every `URLOverride` a request declared, in declaration order, in the shape
    /// both the request resolution and the redirect handling of each executor read them.
    ///
    /// The first request is rewritten once, when it is resolved. A redirect never goes through
    /// resolution again: the executor follows it with whatever URL the `Location` header spelled,
    /// so a response that sends the client back to the host an override stands in for would reach
    /// the real one. This table is part of the session configuration, so each executor can apply
    /// the very same rules to every hop (see ``rewritingRedirect(_:previous:)``).
    ///
    /// It is part of the configuration's identity (`Equatable`): a pooled client follows redirects
    /// with the rules it was built with, and must not be handed to a request that declared others.
    package struct URLOverrides: Sendable, Equatable {

        // MARK: - Inner types

        /// The parsed `"scheme://host[:port][/path]"` shape shared by both sides of a rule.
        package struct Endpoint: Sendable, Equatable {

            package let scheme: String
            package let host: String
            /// `nil` when the endpoint carries no explicit port, which for matching means the
            /// scheme's default (see ``isSameOrigin(as:)``). Kept distinct from `host`, which like
            /// `URLComponents.host` never includes it, so a rule origin/destination declaring a
            /// non-default port doesn't silently match or rewrite to the wrong one.
            package let port: Int?
            package let pathComponents: [String]

            package init(scheme: String, host: String, port: Int?, pathComponents: [String]) {
                self.scheme = scheme
                self.host = host
                self.port = port
                self.pathComponents = pathComponents
            }
        }

        /// A single origin-to-destination pair.
        package struct Rule: Sendable, Equatable {

            package let origin: Endpoint
            package let destination: Endpoint

            package init(origin: Endpoint, destination: Endpoint) {
                self.origin = origin
                self.destination = destination
            }
        }

        /// The destination a request resolves to, and what is left of its path once the matched
        /// prefix was taken off.
        package struct Match: Sendable, Equatable {

            package let destination: Endpoint
            package let remainder: [String]
        }

        // MARK: - Package properties

        package var rules: [Rule]

        package var isEmpty: Bool {
            rules.isEmpty
        }

        // MARK: - Inits

        package init(rules: [Rule] = []) {
            self.rules = rules
        }

        // MARK: - Package methods

        /// The rule that decides where a request to `origin`/`pathComponents` goes: the most
        /// specific one (the longest matching origin path), and among equally specific ones the
        /// last declared.
        ///
        /// Specificity has to come first: `URLOverride([String: String])` declares its rules in
        /// `Dictionary` order, which varies between launches, so "last matching rule wins" alone
        /// picked a different destination from one launch to the next for a whole-host rule plus
        /// a path-scoped one.
        ///
        /// A destination is never matched again, so there is no chaining.
        package func match(origin: Endpoint, pathComponents: [String]) -> Match? {
            var match: (destination: Endpoint, remainder: [String], specificity: Int)?

            for rule in rules {
                guard
                    rule.origin.isSameOrigin(as: origin),
                    pathComponents.starts(with: rule.origin.pathComponents)
                else {
                    continue
                }

                let specificity = rule.origin.pathComponents.count

                if let match, match.specificity > specificity {
                    continue
                }

                match = (rule.destination, Array(pathComponents.dropFirst(specificity)), specificity)
            }

            return match.map { Match(destination: $0.destination, remainder: $0.remainder) }
        }

        /// `url` with the rule that covers it applied, or `nil` when no rule does (or `url` is not
        /// an absolute URL with a host): such a URL is to be requested as it is.
        ///
        /// What `Resolve` does to the first request, for a URL a server named. Query, fragment and
        /// a trailing slash pass through untouched.
        package func rewriting(_ url: String) -> String? {
            guard
                !rules.isEmpty,
                let parsed = URL(string: url),
                var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false),
                let scheme = components.scheme,
                let host = components.host,
                !host.isEmpty
            else {
                return nil
            }

            let encodedPath = components.percentEncodedPath
            // Canonical, like the path components a rule is parsed into.
            let pathComponents = encodedPath.split(separator: "/").map { $0.addingPercentEncodingForURLPath() }

            let origin = Endpoint(scheme: scheme, host: host, port: components.port, pathComponents: [])

            guard let match = match(origin: origin, pathComponents: pathComponents) else {
                return nil
            }

            let rewrittenComponents = match.destination.pathComponents + match.remainder

            var path = ""

            if !rewrittenComponents.isEmpty {
                path = "/" + rewrittenComponents.joined(separator: "/")

                if encodedPath.hasSuffix("/") {
                    path += "/"
                }
            } else if !encodedPath.isEmpty {
                path = "/"
            }

            components.scheme = match.destination.scheme
            components.host = match.destination.host
            components.port = match.destination.port
            components.percentEncodedPath = path

            return components.string
        }

        /// Applies the rules to the next hop of a redirect, in place: `request.url` becomes the
        /// destination a covered `Location` is mapped to, and is left alone otherwise.
        ///
        /// - Parameters:
        ///   - request: The candidate the executor is about to follow, as it built it from the
        ///   `Location`: the URL is what the server named, the headers are what the executor kept.
        ///   - previous: The request that produced the redirect, as it was sent.
        ///
        /// The cross-origin decision is taken on what is actually contacted: the URL the previous
        /// hop was sent to against the URL this one is rewritten to (see
        /// ``Internals/RedirectSanitizer``), not on the `Location` the server wrote. Both
        /// executors compare a candidate with the previous hop *before* anyone has rewritten it,
        /// so a `Location` back to the host an override stands in for looks like another origin
        /// to them (`staging.example` against the `127.0.0.1` it is mapped to) and they take the
        /// credentials off. That is undone here for a hop that, once rewritten, stays on the
        /// origin the previous one went to: the origin a credential was already sent to is not a
        /// new one. A hop that ends on another origin keeps what the executor took off, and has
        /// the rest taken off by the same sanitizer as any other redirect.
        package func rewritingRedirect(
            _ request: inout Internals.RedirectRequest,
            previous: Internals.RedirectRequest?
        ) {
            guard let rewritten = rewriting(request.url) else {
                return
            }

            let wasSameOrigin = previous.map {
                Internals.RedirectSanitizer.isSameOrigin($0.url, request.url)
            }

            request.url = rewritten

            guard
                let previous,
                wasSameOrigin == false,
                Internals.RedirectSanitizer.isSameOrigin(previous.url, rewritten)
            else {
                return
            }

            for name in Internals.RedirectSanitizer.credentialHeaders where !request.headers.contains(name: name) {
                if let value = previous.headers.first(name: name) {
                    request.headers.add(name: name, value: value)
                }
            }
        }
    }
}

// MARK: - Internals.URLOverrides.Endpoint

extension Internals.URLOverrides.Endpoint {

    /// Whether `self` and `other` name the same origin: the same scheme, host and port.
    ///
    /// Scheme and host are compared without regard to case, since neither is case sensitive
    /// (RFC 3986 §3.1, §3.2.2), and a bracketed IPv6 host is the same as the bare one. A port is
    /// compared as the port the connection would use: one left out is the scheme's default, so
    /// `https://example.com` and `https://example.com:443` are the same origin. A port that is not
    /// the default still tells two origins apart, and so does a scheme with no default port.
    package func isSameOrigin(as other: Self) -> Bool {
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

    /// Parses an already-normalized `"scheme://host"` request base URL (see
    /// `RequestConfiguration.baseURL`/`BaseURL`) for matching against a rule's origin.
    ///
    /// Returns `nil` instead of throwing for an empty/malformed value (e.g. no `BaseURL`
    /// declared), since this runs after the property tree has fully resolved, past the point
    /// where a `Property` can still fail the build. An unmatched request should just pass through.
    package init?(baseURL: String) {
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

        self.init(scheme: scheme, host: host, port: port, pathComponents: [])
    }
}
