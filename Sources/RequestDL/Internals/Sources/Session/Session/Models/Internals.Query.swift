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
        map {
            let name = $0.name.addingRFC3986PercentEncoding()
            let value = $0.value.addingRFC3986PercentEncoding()
            return "\(name)=\(value)"
        }.joined(separator: "&")
    }
}
