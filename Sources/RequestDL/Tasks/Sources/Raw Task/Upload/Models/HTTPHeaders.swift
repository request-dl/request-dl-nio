/*
 See LICENSE for this package's licensing information.
 */

import Foundation
import NIOHTTP1

// swiftlint:disable file_length
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

    fileprivate struct Name: Sendable, Hashable, Codable, CustomDebugStringConvertible {

        // MARK: - Internal properties

        let rawValue: String

        var debugDescription: String {
            rawValue
        }

        // MARK: - Private properties

        private let _hashValue: Int

        // MARK: - Inits

        init(_ rawValue: String) {
            self.rawValue = rawValue
            self._hashValue = rawValue.lowercased().hashValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            try self.init(container.decode(String.self, forKey: .rawValue))
        }

        // MARK: - Internal static methods

        static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs._hashValue == rhs._hashValue
        }

        // MARK: - Internal methods

        enum CodingKeys: CodingKey {
            case rawValue
            case _hashValue
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(rawValue, forKey: .rawValue)
        }

        func hash(into hasher: inout Hasher) {
            _hashValue.hash(into: &hasher)
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
        _names.isEmpty
    }

    /**
     Returns the number of headers in the `HTTPHeaders` instance.
    */
    public var count: Int {
        values.lazy.map(\.count).reduce(.zero, +)
    }

    /**
     Returns an array of header names in the `HTTPHeaders` instance.
    */
    public var names: [String] {
        _names.map(\.rawValue)
    }

    /**
     Returns the first name-value pair in the `HTTPHeaders` instance.
     */
    public var first: Element? {
        _names.first.flatMap { name in
            values.first.flatMap {
                $0.first.map {
                    (name.rawValue, $0)
                }
            }
        }
    }

    /**
     Returns the last name-value pair in the `HTTPHeaders` instance.
     */
    public var last: Element? {
        _names.last.flatMap { name in
            values.last.flatMap {
                $0.last.map {
                    (name.rawValue, $0)
                }
            }
        }
    }

    // MARK: - Private properties

    fileprivate var _first: Name? {
        _names.first
    }

    private var values: [[String]]
    private var _names: [Name]

    // MARK: - Inits

    /**
     Initializes an empty `HTTPHeaders` instance.
     */
    public init() {
        self._names = []
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

    /**
     Sets the value of the specified header field.

     - Parameters:
       - name: The name of the header field.
       - value: The value to set for the header field.
     */
    public mutating func set(name: String, value: String) {
        let name = self.name(name)
        let value = trimmingCharacters(value)

        if let index = _names.firstIndex(of: name) {
            values[index] = [value]
        } else {
            _names.append(name)
            values.append([value])
        }
    }

    /**
     Adds a new value to the specified header field.

     - Parameters:
        - name: The name of the header field.
        - value: The value to add for the header field.
     */
    public mutating func add(name: String, value: String) {
        let name = self.name(name)
        let value = trimmingCharacters(value)

        if let index = _names.firstIndex(of: name) {
            values[index].append(value)
        } else {
            _names.append(name)
            values.append([value])
        }
    }

    /**
     Removes the specified header field.

     - Parameter name: The name of the header field to remove.
     */
    public mutating func remove(name: String) {
        _remove(self.name(name))
    }

    /**
     Returns the first occurrence of the value associated with the specified header field name.

     - Parameter name: The name of the header field.
     - Returns: The first occurrence of the value associated with the header field, or `nil`
     if the header field is not found.
     */
    public func first(name: String) -> String? {
        self[name]?.first
    }

    /**
     Returns the last occurrence of the value associated with the specified header field name.

     - Parameter name: The name of the header field.
     - Returns: The last occurrence of the value associated with the header field, or `nil`
     if the header field is not found.
     */
    public func last(name: String) -> String? {
        self[name]?.last
    }

    /**
     Checks if the specified header field exists.

     - Parameter name: The name of the header field.
     - Returns: `true` if the header field exists, `false` otherwise.
     */
    public func contains(name: String) -> Bool {
        _names.contains(self.name(name))
    }

    /**
     Checks if the specified header field exists and satisfies the given closure.

     - Parameters:
        - name: The name of the header field.
        - closure: A closure to evaluate the header field's value.
     - Returns: `true` if the header field exists and satisfies the closure, `false` otherwise.
     - Throws: Any error thrown by the closure.
     */
    public func contains(name: String, where closure: (String) throws -> Bool) rethrows -> Bool {
        guard let index = _names.firstIndex(of: self.name(name)) else {
            return false
        }

        return try values[index].contains(where: closure)
    }

    /**
     Accesses the header field values associated with the specified name.

     - Parameter name: The name of the header field.
     - Returns: An array of values associated with the header field name, or `nil`
     if the header field is not found.
     */
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

        for _name in headers._names {
            let name = _name.rawValue

            guard let values = headers[name] else {
                continue
            }

            if let index = mutableSelf._names.firstIndex(of: _name) {
                let values = try groupingValues(mutableSelf.values[index], values)
                mutableSelf.values[index] = unique(values: values)
            } else {
                for value in values {
                    mutableSelf.add(name: name, value: value)
                }
            }
        }

        return mutableSelf
    }

    public static func == (_ lhs: Self, _ rhs: HTTPHeaders) -> Bool {
        lhs.names.allSatisfy {
            let lhsValues = lhs[$0] ?? []
            let rhsValues = rhs[$0] ?? []
            return lhsValues.allSatisfy {
                rhsValues.contains($0)
            } && lhsValues.count == rhsValues.count
        } && lhs._names.count == rhs._names.count
    }

    // MARK: - Internal methods

    func build() -> NIOHTTP1.HTTPHeaders {
        .init(Array(self))
    }

    // MARK: - Private methods

    fileprivate mutating func _remove(_ name: Name) {
        guard let index = _names.firstIndex(of: name) else {
            return
        }

        _names.remove(at: index)
        values.remove(at: index)
    }

    fileprivate func _values(_ name: Name) -> [String]? {
        guard let index = _names.firstIndex(of: name) else {
            return nil
        }

        return values[index]
    }

    private func unique(values: [String]) -> [String] {
        var merged = [Name]()

        return values.compactMap {
            let value = name(trimmingCharacters($0))

            if merged.contains(value) {
                return nil
            } else {
                merged.append(value)
                return value.rawValue
            }
        }
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
        .init(name: _names.endIndex, value: .zero)
    }

    public subscript(position: Index) -> (name: String, value: String) {
        (
            name: _names[position.name].rawValue,
            value: values[position.name][position.value]
        )
    }

    public func index(before index: Index) -> Index {
        guard index.value == .zero else {
            return .init(
                name: index.name,
                value: values[index.name].index(before: index.value)
            )
        }

        let name = _names.index(before: index.name)
        return .init(
            name: name,
            value: values.startIndex >= name ? values[name].index(before: values[name].endIndex) : values.startIndex
        )
    }

    public func index(after index: Index) -> Index {
        guard values[index.name].endIndex == index.value + 1 else {
            return .init(
                name: index.name,
                value: values[index.name].index(after: index.value)
            )
        }

        let name = _names.index(after: index.name)
        return .init(
            name: name,
            value: name < values.endIndex ? values[name].startIndex : .zero
        )
    }
}

// MARK: - Deprecated

extension HTTPHeaders {

    /**
     Returns an array of header keys in the `HTTPHeaders` instance.
     */
    @available(*, deprecated, renamed: "names")
    public var keys: [String] {
        names
    }

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
// swiftlint:enable file_length
