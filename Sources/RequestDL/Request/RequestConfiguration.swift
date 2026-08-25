//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import RequestDLInternals
import Tracing

/// Configuration object used to define the parameters for an HTTP request.
/// This structure holds details like the base URL, path components, query items,
/// HTTP method, headers, body, and caching policies.
public struct RequestConfiguration: Sendable {

    // MARK: - Public properties

    /// The full URL string constructed from `baseURL`, `pathComponents`, and `queries`.
    ///
    /// - Important: The query items are used as they are. Anything reaching ``queries`` is
    /// expected to be percent encoded already, which is what ``URLEncoder`` produces. Encoding
    /// again here would turn every `%20` into `%2520`.
    public var url: String {
        let cleanBaseURL = baseURL.trimmingURLBoundaryCharacters()
        let pathComponents = pathComponents.joinedAsPath()
        let queries = queries.joined()
        let queriesPathComponent = queries.isEmpty ? "" : "?\(queries)"

        if pathComponents.isEmpty {
            return cleanBaseURL + queriesPathComponent
        } else {
            return "\(cleanBaseURL)/\(pathComponents)\(queriesPathComponent)"
        }
    }

    /// The base URL string for the request. Defaults to an empty string.
    public internal(set) var baseURL: String

    /// An array of path components to be appended to the `baseURL`. Defaults to an empty array.
    public internal(set) var pathComponents: [String]

    /// An array of query items to be added to the request URL. Defaults to an empty array.
    ///
    /// - Important: Percent encoded, see ``url``.
    public internal(set) var queries: [QueryItem]

    /// The HTTP method for the request (e.g., "GET", "POST"). Defaults to `nil`, which implies "GET".
    public internal(set) var method: String?

    /// A collection of HTTP headers to be included in the request. Defaults to an empty header set.
    public internal(set) var headers: HTTPHeaders

    /// The body of the request. Can be `nil` for requests without a body. Defaults to `nil`.
    public internal(set) var body: RequestBody?

    /// The cache policy settings for this request configuration. Defaults to an empty set.
    public internal(set) var cachePolicy: DataCache.Policy.Set

    /// The strategy to use for handling cached data. Defaults to `.ignoreCachedData`.
    public internal(set) var cacheStrategy: CacheStrategy

    /// The `ServiceContext` to bind while this request executes. Defaults to `nil`, which leaves
    /// whatever `ServiceContext.current` task-local is already ambient untouched — only set this
    /// to explicitly override it for this request, independent of the calling task's own state.
    public internal(set) var serviceContext: ServiceContext?

    // MARK: - Internal properties

    /// Only a bodyless GET is cacheable.
    ///
    /// - Important: Must compare the method uppercased. It comes from the caller as a free
    /// string — without normalizing, `.method("get")` disables caching outright while still
    /// behaving as a GET everywhere else. Same normalisation as the query-versus-body decision
    /// in `PayloadNode`.
    var isCacheEnabled: Bool {
        let method = method?.uppercased()
        return body == nil && !cachePolicy.isEmpty && (method == nil || method == "GET")
    }

    var readingMode: Internals.DownloadStep.ReadingMode

    // MARK: - Inits

    init() {
        self.baseURL = ""
        self.pathComponents = []
        self.queries = []
        self.method = nil
        self.headers = .init()
        self.body = nil
        self.readingMode = .length(1_024)
        self.cachePolicy = []
        self.cacheStrategy = .ignoreCachedData
        self.serviceContext = nil
    }

    // MARK: - Internal methods

    /// - Parameter eventLoop: Hosts the task that streams the body, when there is one. See
    /// ``RequestBody/connect(writer:body:eventLoop:)``.
    func build(eventLoop: EventLoop) throws -> HTTPClient.Request {
        try HTTPClient.Request(
            url: url,
            method: method.map { .init(rawValue: $0) } ?? .GET,
            headers: headers.build(),
            body: body?.build(eventLoop: eventLoop)
        )
    }
}

// MARK: - String extension

extension String {

    /// Trims the separators that would otherwise be doubled when this is joined with a path.
    ///
    /// Only whitespace and slashes, at both ends. `"https://example.com/"` loses its trailing
    /// slash, and everything inside is left alone.
    ///
    /// - Important: Must not narrow this down to `.trimmingCharacters(in: .urlHostAllowed.inverted)`
    /// approximated by hand as "alphanumerics and `-._~`" — that set is much narrower than
    /// `urlHostAllowed`, which also carries `[` and `]`, so a base URL with an IPv6 literal would
    /// get mangled: `http://[::1]` coming back as `http://[::1`. Naming what is actually being
    /// removed (whitespace and slashes) is both correct and impossible to get wrong the same way.
    func trimmingURLBoundaryCharacters() -> String {
        trimming { $0 == "/" || $0.isWhitespace }
    }
}
