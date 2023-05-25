/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

extension Internals {

    struct Request: Sendable {

        // MARK: - Internal properties

        var url: String {
            let pathAllowed = CharacterSet(charactersIn: "/")

            let baseURL = baseURL
                .trimmingCharacters(in: .urlHostAllowed.inverted)
                .trimmingCharacters(in: pathAllowed)

            let pathComponents = pathComponents
                .joined(separator: "/")
                .trimmingCharacters(in: .urlPathAllowed.inverted)
                .trimmingCharacters(in: pathAllowed)

            let queries = queries.joined()
            let queriesPathComponent = queries.isEmpty ? "" : "?\(queries)"

            if pathComponents.isEmpty {
                return baseURL + queriesPathComponent
            } else {
                return "\(baseURL)/\(pathComponents)\(queriesPathComponent)"
            }
        }

        var isCacheEnabled: Bool {
            body == nil && !cachePolicy.isEmpty &&
            (method == nil || method == "GET")
        }

        var baseURL: String
        var pathComponents: [String]
        var queries: [Query]

        var method: String?
        var headers: HTTPHeaders

        var body: Body?
        var readingMode: Internals.Response.ReadingMode
        var cachePolicy: DataCache.Policy.Set
        var cacheStrategy: CacheStrategy

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
}
