//
// See LICENSE for this package's licensing information.
//

import Logging
import NIOHTTP1

/// Provides methods and properties for HTTP headers.
///
/// Names are compared case insensitively, per RFC 9110. Values are not, and are stored in the
/// order they were added.
public struct HTTPHeaders: Sendable, Sequence, Codable, Hashable, ExpressibleByDictionaryLiteral {

    /// Walks every name-value pair, one value at a time.
    ///
    /// - Note: Rewritten around a pair of offsets. It used to hold a mutable copy of the whole
    /// header set and delete each name as it finished with it, then call itself. That made
    /// iteration quadratic, since every deletion is a linear search plus a shift, and it
    /// recursed once per header name.
    public struct Iterator: IteratorProtocol {

        // MARK: - Private properties

        private let headers: HTTPHeaders

        private var nameIndex: Int
        private var valueIndex: Int

        // MARK: - Inits

        init(_ headers: HTTPHeaders) {
            self.headers = headers
            self.nameIndex = headers._names.startIndex
            self.valueIndex = .zero
        }

        // MARK: - Public methods

        public mutating func next() -> Element? {
            // A loop rather than a recursive call, and it also copes with a name that somehow
            // holds no values instead of stopping there.
            while nameIndex < headers._names.endIndex {
                let values = headers.values[nameIndex]

                if valueIndex < values.endIndex {
                    defer { valueIndex += 1 }
                    return (headers._names[nameIndex].rawValue, values[valueIndex])
                }

                nameIndex += 1
                valueIndex = .zero
            }

            return nil
        }
    }

    /// A header name, compared without regard to case.
    fileprivate struct Name: Sendable, Hashable, Codable, CustomDebugStringConvertible {

        // MARK: - Internal properties

        let rawValue: String

        var debugDescription: String {
            rawValue
        }

        // MARK: - Private properties

        /// What equality and hashing actually run on.
        ///
        /// - Note: This used to be a stored `hashValue`, and `==` compared nothing else. Two
        /// unrelated names that happened to collide were therefore equal, which silently reads
        /// one header as another. `hashValue` is also explicitly documented as unsuitable for
        /// this: it is seeded per process and is not a substitute for comparing the values.
        private let normalized: String

        // MARK: - Inits

        init(_ rawValue: String) {
            self.rawValue = rawValue
            self.normalized = rawValue.lowercased()
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            try self.init(container.decode(String.self, forKey: .rawValue))
        }

        // MARK: - Internal static methods

        static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.normalized == rhs.normalized
        }

        // MARK: - Internal methods

        /// - Note: The wire format is unchanged, one `rawValue` key, so anything already
        /// persisted still decodes. The unused `_hashValue` case is gone; nothing ever wrote it.
        enum CodingKeys: CodingKey {
            case rawValue
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(rawValue, forKey: .rawValue)
        }

        func hash(into hasher: inout Hasher) {
            normalized.hash(into: &hasher)
        }
    }

    public typealias Key = String
    public typealias Value = String

    public typealias Element = (name: String, value: String)

    // MARK: - Public properties

    /// Indicates whether the instance is empty.
    public var isEmpty: Bool {
        _names.isEmpty
    }

    /// The number of headers name-value pair set.
    public var count: Int {
        values.lazy.map(\.count).reduce(.zero, +)
    }

    /// Returns an array of header names in the headers.
    public var names: [String] {
        _names.map(\.rawValue)
    }

    /// Returns the first name-value pair in the headers.
    public var first: Element? {
        _names.first.flatMap { name in
            values.first.flatMap {
                $0.first.map {
                    (name.rawValue, $0)
                }
            }
        }
    }

    /// Returns the last name-value pair in the headers.
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

    // `fileprivate`, so the iterator and the collection conformance below can read them
    // directly instead of going through a copy.
    fileprivate var values: [[String]]
    fileprivate var _names: [Name]

    // MARK: - Inits

    ///
    /// Initializes an empty headers.
    ///
    public init() {
        self._names = []
        self.values = []
    }

    ///
    /// Initializes an sequence of elements representing header name-value pairs.
    ///
    /// - Parameter headers: A sequence of tuples representing header name-value pairs.
    ///
    public init<S: Sequence>(_ headers: S) where S.Element == (String, String) {
        self.init()

        for (name, value) in headers {
            add(name: name, value: value)
        }
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        self.init(elements)
    }

    init(_ headers: NIOHTTP1.HTTPHeaders) {
        self.init(Array(headers))
    }

    // MARK: - Public methods

    ///
    /// Sets the value of the specified header field, replacing anything already there.
    ///
    /// - Parameters:
    ///   - name: The name of the header field.
    ///   - value: The value to set for the header field.
    ///
    public mutating func set(name: String, value: String) {
        let name = self.name(name)
        let value = trimming(value)

        if let index = _names.firstIndex(of: name) {
            values[index] = [value]
        } else {
            _names.append(name)
            values.append([value])
        }
    }

    ///
    /// Adds a new value to the specified header field, keeping anything already there.
    ///
    /// - Parameters:
    ///    - name: The name of the header field.
    ///    - value: The value to add for the header field.
    ///
    public mutating func add(name: String, value: String) {
        let name = self.name(name)
        let value = trimming(value)

        if let index = _names.firstIndex(of: name) {
            values[index].append(value)
        } else {
            _names.append(name)
            values.append([value])
        }
    }

    ///
    /// Removes the specified header field.
    ///
    /// - Parameter name: The name of the header field to remove.
    ///
    public mutating func remove(name: String) {
        _remove(self.name(name))
    }

    ///
    /// Returns the first occurrence of the value associated with the specified header field name.
    ///
    /// - Parameter name: The name of the header field.
    /// - Returns: The first occurrence of the value associated with the header field, or `nil`
    /// if the header field is not found.
    ///
    public func first(name: String) -> String? {
        self[name]?.first
    }

    ///
    /// Returns the last occurrence of the value associated with the specified header field name.
    ///
    /// - Parameter name: The name of the header field.
    /// - Returns: The last occurrence of the value associated with the header field, or `nil`
    /// if the header field is not found.
    ///
    public func last(name: String) -> String? {
        self[name]?.last
    }

    ///
    /// Checks if the specified header field exists.
    ///
    /// - Parameter name: The name of the header field.
    /// - Returns: `true` if the header field exists, `false` otherwise.
    ///
    public func contains(name: String) -> Bool {
        _names.contains(self.name(name))
    }

    ///
    /// Checks if the specified header field exists and satisfies the given closure.
    ///
    /// - Parameters:
    ///    - name: The name of the header field.
    ///    - closure: A closure to evaluate the header field's value.
    /// - Returns: `true` if the header field exists and satisfies the closure, `false` otherwise.
    /// - Throws: Any error thrown by the closure.
    ///
    public func contains(name: String, where closure: (String) throws -> Bool) rethrows -> Bool {
        guard let index = _names.firstIndex(of: self.name(name)) else {
            return false
        }

        return try values[index].contains(where: closure)
    }

    ///
    /// Accesses the header field values associated with the specified name.
    ///
    /// - Parameter name: The name of the header field.
    /// - Returns: An array of values associated with the header field name, or `nil`
    /// if the header field is not found.
    ///
    public subscript(_ name: String) -> [String]? {
        _values(self.name(name))
    }

    public func makeIterator() -> Iterator {
        Iterator(self)
    }

    /// Folds `headers` into a copy of this one.
    ///
    /// A name carried only by `headers` is appended. A name present on both sides is resolved
    /// by the closure, and whatever it returns is what ends up stored, trimmed but otherwise
    /// untouched.
    ///
    /// - Parameters:
    ///   - headers: The set to merge in.
    ///   - groupingValues: Resolves a name present on both sides. **The receiver's values are
    ///   passed first**, the incoming ones second, so `{ mine, _ in mine }` keeps this set and
    ///   `{ _, theirs in theirs }` lets the argument win.
    ///
    /// - Note: No longer removes repeated values. It used to, on the both-present branch only,
    /// which made the operation asymmetric and, worse, made it disagree with the closure: a
    /// caller writing `{ mine, theirs in mine + theirs }` did not get back `mine + theirs`, and
    /// `{ mine, _ in mine }` was not even an identity, since it could drop values `mine` had
    /// legitimately carried twice. Deduplication is a policy, not an invariant, and it is wrong
    /// for `Set-Cookie` and `Via`. It lives in ``uniquingValues()`` now, for callers that want
    /// it. Trimming stays, because that one *is* an invariant of the storage.
    public func merging(
        _ headers: HTTPHeaders,
        by groupingValues: ([String], [String]) throws -> [String]
    ) rethrows -> HTTPHeaders {
        var mutableSelf = self

        for name in headers._names {
            guard let incoming = headers._values(name) else {
                continue
            }

            guard let index = mutableSelf._names.firstIndex(of: name) else {
                // Appended directly. Calling `add` per value repeated the name lookup once per
                // value, for a name we already know is not there.
                mutableSelf._names.append(name)
                mutableSelf.values.append(incoming.map(trimming))
                continue
            }

            mutableSelf.values[index] = try groupingValues(mutableSelf.values[index], incoming)
                .map(trimming)
        }

        return mutableSelf
    }

    /// Returns a copy with repeated values removed under each name, keeping the first of each
    /// and the original order.
    ///
    /// - Warning: Not safe for every field, which is why it is opt-in rather than something
    /// ``merging(_:by:)`` does on its own.
    ///
    ///   - `Set-Cookie` must never go through this. RFC 6265 defines it as one cookie per
    ///   field line and forbids folding, so the lines are independent by design.
    ///   - `Via` uses repetition for loop detection: the same proxy appearing twice is the
    ///   signal, and collapsing it destroys the evidence.
    ///   - Anything where order or multiplicity carries meaning, such as `WWW-Authenticate`
    ///   challenges, is in the same category.
    ///
    ///   It is safe for the idempotent list fields, `Accept`, `Accept-Encoding`,
    ///   `Cache-Control`, `Connection`, `Vary`, `Allow`, where a repeat says nothing new.
    public func uniquingValues() -> HTTPHeaders {
        var mutableSelf = self

        for index in mutableSelf.values.indices {
            var seen = Set<String>()
            mutableSelf.values[index] = mutableSelf.values[index].filter { seen.insert($0).inserted }
        }

        return mutableSelf
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

    private func name(_ name: String) -> Name {
        .init(name)
    }

    /// - Note: Uses the package's own trimming. It was `trimmingCharacters(in: .whitespaces)`,
    /// which needs `Foundation.CharacterSet`, a type this file has no import for and that the
    /// refactor is removing.
    private func trimming(_ value: String) -> String {
        value.trimming(where: \.isWhitespace)
    }
}

// MARK: - BidirectionalCollection

// Demoted from `RandomAccessCollection`. The storage is a jagged array of arrays, so moving an
// index by *n* costs a walk over the names; claiming random access told generic algorithms they
// could jump around for free, which is how an O(n) header lookup becomes O(n²) inside somebody
// else's code.
extension HTTPHeaders: BidirectionalCollection {

    public struct Index: Comparable {

        fileprivate let name: Int
        fileprivate let value: Int

        /// - Note: Lexicographic. It was `lhs.name < rhs.name && lhs.value < rhs.value`, which
        /// is not an ordering at all: `(0, 1)` and `(1, 0)` are neither less than, greater than,
        /// nor equal to each other, so anything relying on `Comparable` behaved arbitrarily.
        public static func < (_ lhs: Self, _ rhs: Self) -> Bool {
            (lhs.name, lhs.value) < (rhs.name, rhs.value)
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

    public func index(after index: Index) -> Index {
        let values = self.values[index.name]
        let next = index.value + 1

        guard next < values.endIndex else {
            // Past the last value of this name, so on to the next one. When that was the last
            // name this lands exactly on `endIndex`.
            return .init(name: index.name + 1, value: .zero)
        }

        return .init(name: index.name, value: next)
    }

    /// - Note: The previous version tested `values.startIndex >= name`, which is only true for
    /// the very first name, so stepping back into any other name landed on its first value
    /// rather than its last. Iterating backwards repeated the same element and never terminated
    /// where it should.
    public func index(before index: Index) -> Index {
        guard index.value == .zero else {
            return .init(name: index.name, value: index.value - 1)
        }

        let name = index.name - 1
        return .init(name: name, value: values[name].endIndex - 1)
    }
}

// MARK: - CustomDebugStringConvertible

extension HTTPHeaders: CustomDebugStringConvertible {

    public var debugDescription: String {
        var lines: [String] = []

        for name in _names {
            for value in _values(name) ?? [] {
                lines.append("\(name.rawValue): \(value)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
