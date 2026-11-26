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
/// domain cutovers, not to bypassing DNS or tunneling through an intermediary, which is what
/// ``DNSOverride``/``Proxy`` are for.
///
/// It is unrelated to `Session.disableRedirect()`/`.enableRedirectFollow(...)` as a *policy*,
/// despite the naming proximity: those decide whether HTTP 3xx responses returned by the server
/// are followed, while `URLOverride` never decides that. It does, though, keep applying to the
/// hops of a redirect that is followed (see "Redirects" below).
///
/// ## Redirects
///
/// The override is applied to every hop of a redirect, not only to the first request: a `Location`
/// that names a host (scheme, host and port) one of the rules covers is rewritten with that rule,
/// the same way the request was, on both executors. A response of the staging server redirecting
/// back to `https://staging.example.com/login` therefore keeps reaching the destination the
/// override maps it to, instead of the real `staging.example.com`.
///
/// ```swift
/// DataTask {
///     BaseURL("staging.example.com")
///     Path("start")
///     URLOverride("http://127.0.0.1:8080", from: "https://staging.example.com")
/// }
/// // GET http://127.0.0.1:8080/start
/// // 302, Location: https://staging.example.com/login
/// // GET http://127.0.0.1:8080/login   <- still the destination, not the real host
/// ```
///
/// - A `Location` that no rule covers (another host, scheme or port) is followed exactly as the
///   server wrote it. An override never redirects traffic that wasn't addressed to its origin.
/// - A relative `Location` is resolved against the host the previous hop was actually sent to,
///   which is already the destination, so it needs no rule.
/// - A path-scoped rule replaces its matched prefix on a hop as it does on the request, and
///   rules are chosen the same way (most specific first, then the last declared). The destination
///   is never matched again, so there is no chaining.
/// - What ``RedirectStrategy`` and `Session.onRedirect(_:)` receive is already the rewritten
///   request, which is also what the history records of every earlier hop. A URL a strategy
///   answers with that differs from the one it was handed is a `Location` of its own and goes
///   through the rules too.
///
/// Whether a hop leaves the origin (and so loses `Authorization`, `Cookie`, `Origin`,
/// `Proxy-Authorization` and an explicit `Host`, like any redirect to another origin) is decided
/// on the destinations actually contacted: the one the previous hop was sent to against the one
/// this hop is rewritten to, not on the `Location` the server wrote, which names a host that is
/// never contacted. So a redirect back to the overridden host stays on the origin the request was
/// sent to and keeps its credentials, as a redirect that never left it does, and a redirect to
/// any other destination, overridden or not, is another origin and loses them. An override can't
/// send credentials anywhere the request wasn't already going.
///
/// > Note: Two hosts overridden to the *same* destination are, for this check, the same origin:
/// > both are sent to one place, which already received the credentials.
///
/// A redirect that a rule covers but whose destination cannot be built as a URL fails with an
/// error instead of being followed to the host the server wrote, which is the one the rule
/// stands in for.
///
/// > Important: The proxy is chosen once, for the destination of the first request, and every hop
/// > of a redirect goes through that same proxy (or none): neither an explicit ``Proxy`` nor
/// > ``SystemProxy`` (its bypass list or PAC script included) is consulted again for the host a
/// > hop is rewritten or redirected to. With rules, a redirect from an overridden host to one no
/// > rule covers, or the other way round, can therefore reach a host through a proxy that
/// > would not have been used for it on its own, or around one that would have been.
///
/// > Important: A ``BackgroundDownloadTask`` is followed through redirects by the system, which
/// > gives the app no chance to rewrite a hop: the override applies to the request that starts it.
///
/// Both initializers take full `"scheme://host[/path]"` strings, never a bare host, so the
/// `://` keeps parsing unambiguous and the scheme mandatory, the same way ``BaseURL`` validates
/// its own host string.
///
/// ```swift
/// // Single pair: composes with @PropertyBuilder conditionals (if/else picking one override)
/// URLOverride("https://apple.com", from: "https://google.com")
///
/// // Dictionary: bulk declaration of the whole table up front
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
/// > Note: A destination is never re-matched against other `URLOverride` rules, so there is no
/// > chaining, which avoids override loops.
///
/// > Note: When several rules match, the most specific one wins: the one whose origin path
/// > matches the most leading path components (so a path-scoped rule beats a whole-host rule for
/// > the same host). Among equally specific rules, the last declared wins, the same convention
/// > ``BaseURL`` and ``DNSOverride`` already use. Specificity is what makes the dictionary form
/// > deterministic, since a `Dictionary`'s iteration order varies between launches.
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
        // Sorted by origin: a `Dictionary` iterates in an order that changes from one build of it
        // to the next, and the rules are part of the session configuration's identity (the pool
        // key), so the same table has to produce the same rules every time.
        self.pairs = overrides.sorted { $0.key < $1.key }.map { (origin: $0.key, destination: $0.value) }
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
