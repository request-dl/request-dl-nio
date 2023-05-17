/*
 See LICENSE for this package's licensing information.
 */

import Foundation
import NIOHTTP1

/**
 A structure that represents HTTP headers.

 `HTTPHeaders` provides methods and properties for working with HTTP headers in Swift.
 */
public struct HTTPHeaders: Sendable, Sequence, Codable, Hashable, ExpressibleByDictionaryLiteral {

    public struct Iterator: IteratorProtocol {

        // MARK: - Private properties

        fileprivate var headers: HTTPHeaders

        private var name: Name?
        private var values: [String]?

        init(_ headers: HTTPHeaders) {
            let name = headers._first
            let values = name.flatMap {
                headers._values($0)
            }

            self.headers = headers
            self.name = name
            self.values = values
        }

        // MARK: - Internal methods

        public mutating func next() -> Element? {
            guard let name = name else {
                return nil
            }

            if var values, !values.isEmpty {
                let value = values.removeFirst()
                self.values = values
                return (name.rawValue, value)
            }

            headers._remove(name)

            self.name = headers._first
            self.values = self.name.flatMap {
                headers._values($0)
            }

            return next()
        }
    }

    fileprivate struct Name: Sendable, Hashable, Codable {

        // MARK: - Internal properties

        let rawValue: String

        // MARK: - Private properties

        private var _hashValue: Int

        // MARK: - Inits

        init(_ rawValue: String) {
            self.rawValue = rawValue
            self._hashValue = rawValue.lowercased().hashValue
        }

        // MARK: - Internal static methods

        static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs._hashValue == rhs._hashValue
        }

        // MARK: - Internal methods

        func hash(into hasher: inout Hasher) {
            hasher.combine(_hashValue)
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
        keys.isEmpty
    }

    /**
     Returns the number of headers in the `HTTPHeaders` instance.
    */
    public var count: Int {
        values.lazy.map(\.count).reduce(.zero, +)
    }

    /**
     Returns an array of header keys in the `HTTPHeaders` instance.
    */
    public var keys: [String] {
        names.map(\.rawValue)
    }

    public var first: Element? {
        names.first.flatMap { name in
            values.first.flatMap {
                $0.first.map {
                    (name.rawValue, $0)
                }
            }
        }
    }

    public var last: Element? {
        names.last.flatMap { name in
            values.last.flatMap {
                $0.last.map {
                    (name.rawValue, $0)
                }
            }
        }
    }

    // MARK: - Private properties

    fileprivate var _first: Name? {
        names.first
    }

    private var names: [Name]
    private var values: [[String]]

    // MARK: - Inits

    /**
     Initializes an empty `HTTPHeaders` instance.
     */
    public init() {
        self.names = []
        self.values = []
    }

    /**
     Initializes an `HTTPHeaders` instance with an sequence of elements representing header name-value pairs.

     - Parameter headers: An array of tuples representing header key-value pairs.
     */

    public init<S: Sequence>(_ headers: S) where S.Element == (String, String) {
        self.init()

        for (name, value) in headers {
            add(name: name, value: value)
        }
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        self.init(elements)
    }

    /**
     Initializes an `HTTPHeaders` instance with a dictionary representing header key-value pairs.

     - Parameter dictionary: A dictionary representing header key-value pairs.
     */
    @available(*, deprecated)
    public init(_ dictionary: [String: String]) {
        self.init(Array(dictionary).map { ($0, $1) })
    }

    init(_ headers: NIOHTTP1.HTTPHeaders) {
        self.init(Array(headers))
    }

    // MARK: - Public methods

    public mutating func set(name: String, value: String) {
        let name = self.name(name)
        let value = trimmingCharacters(value)

        if let index = names.firstIndex(of: name) {
            values[index] = [value]
        } else {
            names.append(name)
            values.append([value])
        }
    }

    public mutating func add(name: String, value: String) {
        let name = self.name(name)
        let value = trimmingCharacters(value)

        if let index = names.firstIndex(of: name) {
            values[index].append(value)
        } else {
            names.append(name)
            values.append([value])
        }
    }

    public mutating func remove(name: String) {
        _remove(self.name(name))
    }

    public func first(name: String) -> String? {
        self[name]?.first
    }

    public func last(name: String) -> String? {
        self[name]?.last
    }

    public func contains(name: String) -> Bool {
        names.contains(self.name(name))
    }

    public func contains(name: String, where closure: (String) throws -> Bool) rethrows -> Bool {
        guard let index = names.firstIndex(of: self.name(name)) else {
            return false
        }

        return try values[index].contains(where: closure)
    }

    public subscript(_ name: String) -> [String]? {
        _values(self.name(name))
    }

    public func makeIterator() -> Iterator {
        Iterator(self)
    }

    public func merging(
        _ headers: HTTPHeaders,
        by groupingValues: ([String], [String]) throws -> [String]
    ) rethrows -> HTTPHeaders {
        var mutableSelf = self

        for _name in headers.names {
            let name = _name.rawValue

            guard let values = headers[name] else {
                continue
            }

            if let index = mutableSelf.names.firstIndex(of: _name) {
                mutableSelf.values[index] = try Array(Set(
                    groupingValues(mutableSelf.values[index], values)
                ))
            } else {
                for value in values {
                    mutableSelf.add(name: name, value: value)
                }
            }
        }

        return mutableSelf
    }

    // MARK: - Internal methods

    func build() -> NIOHTTP1.HTTPHeaders {
        .init(Array(self))
    }

    // MARK: - Private methods

    fileprivate mutating func _remove(_ name: Name) {
        guard let index = names.firstIndex(of: name) else {
            return
        }

        names.remove(at: index)
        values.remove(at: index)
    }

    fileprivate func _values(_ name: Name) -> [String]? {
        guard let index = names.firstIndex(of: name) else {
            return nil
        }

        return values[index]
    }

    private func name(_ name: String) -> Name {
        .init(name)
    }

    private func trimmingCharacters(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
    }
}

extension HTTPHeaders: RandomAccessCollection {

    public struct Index: Comparable {

        fileprivate let name: Int
        fileprivate let value: Int

        public static func < (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.name < rhs.name && lhs.value < rhs.value
        }
    }

    public var startIndex: Index {
        .init(name: .zero, value: .zero)
    }

    public var endIndex: Index {
        .init(name: names.endIndex, value: values.last?.endIndex ?? values.endIndex)
    }

    public subscript(position: Index) -> (name: String, value: String) {
        (
            name: names[position.name].rawValue,
            value: values[position.name][position.value]
        )
    }

    public func index(before i: Index) -> Index {
        guard values[i.name].startIndex == i.value else {
            return .init(
                name: i.name,
                value: values[i.name].index(before: i.value)
            )
        }

        let name = names.index(before: i.name)
        return .init(
            name: name,
            value: values[name].endIndex
        )
    }

    public func index(after i: Index) -> Index {
        guard values[i.name].endIndex == i.value else {
            return .init(
                name: i.name,
                value: values[i.name].index(after: i.value)
            )
        }

        let name = names.index(after: i.name)
        return .init(
            name: name,
            value: values[name].startIndex
        )
    }
}

// MARK: - Deprecated

extension HTTPHeaders {

    /**
     Retrieves the value for a given header key.

     - Parameter key: The key of the header.

     - Returns: The value associated with the given header key, or `nil` if the header key is not found.
     */
    @available(*, deprecated, renamed: "subscript(_:)")
    public func getValue(forKey key: String) -> String? {
        self[key]?.joined(separator: ", ")
    }

    /**
     Sets the value for a given header key.

     - Parameters:
        - value: The value to set for the header.
        - key: The key of the header.
     */
    @available(*, deprecated, renamed: "set(name:value:)")
    public mutating func setValue(_ value: String, forKey key: String) {
        remove(name: key)

        for value in value.split(separator: ",") {
            add(name: key, value: String(value))
        }
    }
}
