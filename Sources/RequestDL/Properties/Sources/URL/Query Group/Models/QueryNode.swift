/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct QueryNode: PropertyNode {

    // MARK: - Internal properties

    let name: String
    let value: Sendable
    let urlEncoder: URLEncoder

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        let queries = try urlEncoder.encode(value, forKey: name).map {
            $0.build()
        }

        make.requestConfiguration.queries.append(contentsOf: queries)
    }
}
