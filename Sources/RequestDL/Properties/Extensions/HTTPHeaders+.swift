/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension HTTPHeaders {

    func components(name: String) -> LazyMapSequence<[Substring], String>? {
        self[name]?
            .reduce([]) { $0 + $1.split(separator: ",") }
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
