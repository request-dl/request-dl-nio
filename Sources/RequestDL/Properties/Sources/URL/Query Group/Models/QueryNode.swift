/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct QueryNode: PropertyNode {

    private let name: String
    private let value: Any
    private let urlEncoder: URLEncoder

    init(
        name: String,
        value: Any,
        urlEncoder: URLEncoder
    ) {
        self.name = name
        self.value = value
        self.urlEncoder = urlEncoder
    }

    func make(_ make: inout Make) async throws {
        let queries = try urlEncoder.encode(value, forKey: name).map {
            $0.build()
        }

        make.request.queries.append(contentsOf: queries)
    }
}
