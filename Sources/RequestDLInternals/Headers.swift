/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Headers {

    private var headers: [String: String]

    init() {
        self.headers = [:]
    }

    init(_ array: [(String, String)]) {
        var dictionary = [String: String]()

        for (name, value) in array {
            dictionary[name] = value
        }

        self.headers = dictionary
    }

    public mutating func setValue(_ value: String, forKey key: String) {
        headers[key] = value
    }

    public func getValue(forKey key: String) -> String? {
        headers[key]
    }

    public var allHeaderFields: [String: String] {
        headers
    }

    func build() ->  [(String, String)] {
        headers.map { ($0, $1) }
    }
}
