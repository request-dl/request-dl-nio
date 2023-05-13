/*
 See LICENSE for this package's licensing information.
 */

import Foundation

/**
 A structure that represents HTTP headers.

 `HTTPHeaders` provides methods and properties for working with HTTP headers in Swift.
 */
public struct HTTPHeaders: Hashable, Sendable {

    // MARK: - Public methods

    /**
     Indicates whether the `HTTPHeaders` instance is empty.
     */
    public var isEmpty: Bool {
        headers.isEmpty
    }

    /**
     Returns the number of headers in the `HTTPHeaders` instance.
    */
    public var count: Int {
        headers.count
    }

    /**
     Returns an array of header keys in the `HTTPHeaders` instance.
    */
    public var keys: [String] {
        headers.map(\.0)
    }

    // MARK: - Private properties

    fileprivate var headers: Internals.Headers

    // MARK: - Inits

    /**
     Initializes an empty `HTTPHeaders` instance.
     */
    public init() {
        self.headers = .init([])
    }

    /**
     Initializes an `HTTPHeaders` instance with an array of tuples representing header key-value pairs.

     - Parameter headers: An array of tuples representing header key-value pairs.
     */
    public init(_ headers: [(String, String)]) {
        self.headers = .init(headers)
    }

    /**
     Initializes an `HTTPHeaders` instance with a dictionary representing header key-value pairs.

     - Parameter dictionary: A dictionary representing header key-value pairs.
     */
    public init(_ dictionary: [String: String]) {
        self.init(Array(dictionary))
    }

    init(_ headers: Internals.Headers) {
        self.headers = headers
    }

    // MARK: - Public methods

    /**
     Retrieves the value for a given header key.

     - Parameter key: The key of the header.

     - Returns: The value associated with the given header key, or `nil` if the header key is not found.
     */
    public func getValue(forKey key: String) -> String? {
        headers.getValue(forKey: key)
    }

    /**
     Sets the value for a given header key.

     - Parameters:
        - value: The value to set for the header.
        - key: The key of the header.
     */
    public mutating func setValue(_ value: String, forKey key: String) {
        headers.setValue(value, forKey: key)
    }

    public func makeIterator() -> Iterator {
        .init(headers: headers.makeIterator())
    }
}

extension HTTPHeaders: Sequence {

    public typealias Element = (String, String)

    public struct Iterator: IteratorProtocol {

        // MARK: - Private properties

        fileprivate var headers: Internals.Headers.Iterator

        // MARK: - Public methods

        public mutating func next() -> Element? {
            headers.next()
        }
    }
}

// MARK: - Internals.Headers extension

extension Internals.Headers {

    init(_ headers: HTTPHeaders) {
        self = headers.headers
    }
}
