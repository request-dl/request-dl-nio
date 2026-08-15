//
// See LICENSE for this package's licensing information.
//

/// `URLOverride` rewrites a request's scheme, host, and optionally a path prefix to a different
/// destination, resolved before the request executes.
///
/// ```swift
/// DataTask {
///     BaseURL("google.com")
///     URLOverride("https://apple.com", from: "https://google.com")
/// }
/// // executes against apple.com
/// ```
///
/// Unlike ``DNSOverride``, which redirects the connection while keeping the request's `Host`
/// header and TLS SNI pointed at the original hostname, `URLOverride` rewrites the request
/// itself: the destination server sees `Host: apple.com` and gets real TLS certificate validation
/// against its own certificate, not the origin's. This makes it suited to migrating an API to a
/// new domain without touching every ``BaseURL`` call site, environment overrides, or staged
/// domain cutovers — not to bypassing DNS or tunneling through an intermediary, which is what
/// ``DNSOverride``/``Proxy`` are for.
///
/// It is also unrelated to `Session.disableRedirect()`/`.enableRedirectFollow(...)`, despite the
/// naming proximity — those follow HTTP 3xx responses returned by the server; `URLOverride` never
/// sees a 3xx, it rewrites the request before it is ever sent.
///
/// Both initializers take full `"scheme://host[/path]"` strings — never a bare host — so the
/// `://` keeps parsing unambiguous and the scheme mandatory, the same way ``BaseURL`` validates
/// its own host string.
///
/// ```swift
/// // Single pair — composes with @PropertyBuilder conditionals (if/else picking one override)
/// URLOverride("https://apple.com", from: "https://google.com")
///
/// // Dictionary — bulk declaration of the whole table up front
/// URLOverride([
///     "https://google.com": "https://apple.com",
///     "https://google.com/api/v1": "https://apple.com/v2",
/// ])
/// ```
///
/// The origin's path, if present, is matched as a prefix of path components, not a raw string, so
/// `api/v1` never accidentally matches `api/v10`. On a match, the matched leading path components
/// are replaced with the destination's; the remainder of the path and the query string pass
/// through untouched.
///
/// > Note: A destination is never re-matched against other `URLOverride` rules — there is no
/// > chaining, which avoids override loops.
///
/// > Note: The last-declared rule wins for a given origin, the same convention ``BaseURL`` and
/// > ``DNSOverride`` already use. If two declared rules have a genuinely overlapping-but-different
/// > scope for the same host (e.g. a whole-host rule and a path-scoped rule both declared), which
/// > one applies is left undefined rather than adding specificity-ordering complexity.
public struct URLOverride: Property {

    private struct Node: PropertyNode {

        let pairs: [(origin: String, destination: String)]

        func make(_ make: inout Make) async throws {
            for pair in pairs {
                make.urlOverrides.append(
                    URLOverrideRule(
                        origin: try URLOverrideEndpoint(parsing: pair.origin),
                        destination: try URLOverrideEndpoint(parsing: pair.destination)
                    )
                )
            }
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let pairs: [(origin: String, destination: String)]

    // MARK: - Inits

    ///
    /// Initializes a new instance of `URLOverride` mapping a single origin to a destination.
    ///
    /// - Parameters:
    ///    - destination: The full `"scheme://host[/path]"` requests matching `origin` are rewritten to.
    ///    - origin: The full `"scheme://host[/path]"` to match against the resolved request.
    ///
    /// > Note: The parameter order is `(_ destination, from origin)`, meaning `origin` requests
    /// resolve to `destination`, mirroring ``DNSOverride``.
    ///
    public init(_ destination: String, from origin: String) {
        self.pairs = [(origin: origin, destination: destination)]
    }

    ///
    /// Initializes a new instance of `URLOverride` declaring the whole origin-to-destination
    /// table at once.
    ///
    /// - Parameter overrides: A dictionary keyed by the full `"scheme://host[/path]"` origin,
    /// valued by the full `"scheme://host[/path]"` destination it resolves to.
    ///
    public init(_ overrides: [String: String]) {
        self.pairs = overrides.map { (origin: $0.key, destination: $0.value) }
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<URLOverride>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(pairs: property.pairs))
    }
}
