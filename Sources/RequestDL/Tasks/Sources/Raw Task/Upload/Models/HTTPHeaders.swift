/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct HTTPHeaders: Hashable, Sendable {

    private var headers: Internals.Headers

    public init() {
        self.headers = .init([])
    }

    init(_ headers: Internals.Headers) {
        self.headers = headers
    }

    public init(_ headers: [(String, String)]) {
        self.headers = .init(headers)
    }

    public init(_ dictionary: [String: String]) {
        self.init(Array(dictionary))
    }

    public func getValue(forKey key: String) -> String? {
        headers.getValue(forKey: key)
    }

    public mutating func setValue(_ value: String, forKey key: String) {
        headers.setValue(value, forKey: key)
    }
}

extension HTTPHeaders {

    public var isEmpty: Bool {
        headers.isEmpty
    }

    public var count: Int {
        headers.count
    }
}

extension HTTPHeaders {

    public var keys: [String] {
        headers.map(\.0)
    }
}
