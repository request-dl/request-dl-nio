/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

public struct RequestConfiguration: Sendable {

    // MARK: - Public properties

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

    public internal(set) var baseURL: String
    public internal(set) var pathComponents: [String]
    public internal(set) var queries: [QueryItem]

    public internal(set) var method: String?
    public internal(set) var headers: HTTPHeaders
    
    public internal(set) var body: RequestBody?

    public internal(set) var cachePolicy: DataCache.Policy.Set
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
