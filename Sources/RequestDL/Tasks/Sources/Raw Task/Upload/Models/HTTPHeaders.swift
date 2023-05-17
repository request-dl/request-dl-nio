/*
 See LICENSE for this package's licensing information.
 */

import Foundation

/**
 A structure that represents HTTP headers.

 `HTTPHeaders` provides methods and properties for working with HTTP headers in Swift.
 */
public struct HTTPHeaders: Sendable, Sequence, Hashable, ExpressibleByDictionaryLiteral {

    public struct Iterator: Sendable, IteratorProtocol {

        // MARK: - Private properties

        fileprivate var headers: Internals.Headers.Iterator

        // MARK: - Public methods

        public mutating func next() -> Element? {
            headers.next()
        }
    }

    public typealias Key = String
    public typealias Value = String

    public typealias Element = (name: String, value: String)

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

    public init(dictionaryLiteral elements: (String, String)...) {
        self.init(elements)
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

    public subscript(_ key: String) -> [String]? {
        headers[key]
    }

    public mutating func set(name: String, value: String) {
        headers.set(name: name, value: value)
    }

    public mutating func add(name: String, value: String) {
        headers.add(name: name, value: value)
    }

    public func contains(name: String) -> Bool {
        headers.contains(name: name)
    }

    public func contains(_ value: String, for name: String) -> Bool {
        headers.contains(value, for: name)
    }

    /**
     Retrieves the value for a given header key.

     - Parameter key: The key of the header.

     - Returns: The value associated with the given header key, or `nil` if the header key is not found.
     */
    @available(*, deprecated, renamed: "subscript(_:)")
    public func getValue(forKey key: String) -> String? {
        headers[key]?.joined(separator: ", ")
    }

    /**
     Sets the value for a given header key.

     - Parameters:
        - value: The value to set for the header.
        - key: The key of the header.
     */
    @available(*, deprecated, renamed: "set(name:value:)")
    public mutating func setValue(_ value: String, forKey key: String) {
        headers.set(name: key, value: value)
    }

    public func makeIterator() -> Iterator {
        .init(headers: headers.makeIterator())
    }
}

extension HTTPHeaders: RandomAccessCollection {

    public struct Index: Comparable {

        fileprivate let index: Internals.Headers.Index

        public static func < (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.index < rhs.index
        }
    }

    public var startIndex: Index {
        .init(index: headers.startIndex)
    }

    public var endIndex: Index {
        .init(index: headers.endIndex)
    }

    public subscript(position: Index) -> (name: String, value: String) {
        headers[position.index]
    }

    public func index(before i: Index) -> Index {
        .init(index: headers.index(before: i.index))
    }

    public func index(after i: Index) -> Index {
        .init(index: headers.index(after: i.index))
    }
}

// MARK: - Internals.Headers extension

extension Internals.Headers {

    init(_ headers: HTTPHeaders) {
        self = headers.headers
    }
}
