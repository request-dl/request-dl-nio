/*
See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

/**
 Configuration object used to define the parameters for an HTTP request.
 This structure holds details like the base URL, path components, query items,
 HTTP method, headers, body, and caching policies.
 */
public struct RequestConfiguration: Sendable {

    // MARK: - Public properties

    /**
     The full URL string constructed from `baseURL`, `pathComponents`, and `queries`.

     This computed property builds the URL by combining the configured components.
     It automatically trims unnecessary slashes and handles query string formatting.
     */
    public var url: String {
        let baseURL = baseURL
            .trimmingCharacters(in: .urlHostAllowed.inverted)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let pathComponents = pathComponents.joinedAsPath()

        let queries = queries.joined()
        let queriesPathComponent = queries.isEmpty ? "" : "?\(queries)"

        if pathComponents.isEmpty {
            return baseURL + queriesPathComponent
        } else {
            return "\(baseURL)/\(pathComponents)\(queriesPathComponent)"
        }
    }

    /// The base URL string for the request. Defaults to an empty string.
    public internal(set) var baseURL: String

    /// An array of path components to be appended to the `baseURL`. Defaults to an empty array.
    public internal(set) var pathComponents: [String]

    /// An array of query items to be added to the request URL. Defaults to an empty array.
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

    // MARK: - Internal properties

    var isCacheEnabled: Bool {
        body == nil && !cachePolicy.isEmpty &&
        (method == nil || method == "GET")
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
    }

    // MARK: - Internal methods

    func build() throws -> HTTPClient.Request {
        try HTTPClient.Request(
            url: url,
            method: method.map { .init(rawValue: $0) } ?? .GET,
            headers: headers.build(),
            body: body?.build()
        )
    }
}
