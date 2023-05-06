/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct Query {
        let name: String
        let value: String
    }
}

extension [Internals.Query] {

    func joined() -> String {
        map { "\($0.name)=\($0.value)" }
            .joined(separator: "&")
    }
}
