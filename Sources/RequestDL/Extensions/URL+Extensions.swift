/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URL {

    func appendingQueries(_ queries: [URLQueryItem]) -> URL {
        guard var components = URLComponents(
            url: self,
            resolvingAgainstBaseURL: true
        ) else { return self }

        var queryItems = components.queryItems ?? []

        for query in queries {
            queryItems.append(query)
        }

        components.queryItems = queryItems
        return components.url ?? self
    }
}

