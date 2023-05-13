/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct QueryNode: PropertyNode {

    let name: String
    let value: Any
    let urlEncoder: URLEncoder

    func make(_ make: inout Make) async throws {
        let queries = try urlEncoder.encode(value, forKey: name).map {
            $0.build()
        }

        make.request.queries.append(contentsOf: queries)
    }
}
