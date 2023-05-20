/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct Query: Sendable, Equatable, Hashable {
        let name: String
        let value: String
    }
}

// MARK: - [Internals.Query] extension

extension [Internals.Query] {

    func joined() -> String {
        map { "\($0.name)=\($0.value)" }
            .joined(separator: "&")
    }
}
