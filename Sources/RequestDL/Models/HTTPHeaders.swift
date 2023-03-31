/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A structure for HTTP headers.
public struct HTTPHeaders: Hashable, Sendable {

    private var headers: [String: String]

    /// Initializes a new instance of `HTTPHeaders`.
    public init() {
        self.headers = [:]
    }

    /**
     Initializes a new instance of `HTTPHeaders` with the given array of header tuples.

     - Parameter headers: An array of header tuples.
     */
    public init(_ headers: [(String, String)]) {
        self.headers = .init(headers) { key, _ in key }
    }

    /**
     Initializes a new instance of `HTTPHeaders` with the given dictionary of headers.

     - Parameter dictionary: A dictionary of headers.
     */
    public init(_ dictionary: [String: String]) {
        self.init(Array(dictionary))
    }

    /**
     Returns the value for the given header key.

     - Parameter key: The header key.

     - Returns: The value for the given header key, or `nil` if the key does not exist.
     */
    public func getValue(forKey key: String) -> String? {
        headers[key]
    }

    /**
     Sets the value for the given header key.

     - Parameters:
        - value: The value to set.
        - key: The header key.
     */
    public mutating func setValue(_ value: String, forKey key: String) {
        headers[key] = value
    }
}

extension HTTPHeaders {

    /// Returns a Boolean value indicating whether the headers are empty.
    public var isEmpty: Bool {
        headers.isEmpty
    }

    /// Returns the number of headers.
    public var count: Int {
        headers.count
    }
}

extension HTTPHeaders {

    /// Returns an array of the header keys.
    public var keys: [String] {
        headers.map(\.0)
    }
}
