/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOHTTP1

extension Internals {

    struct Headers: Sendable, Sequence, Codable, Hashable {

        struct Iterator: IteratorProtocol {

            // MARK: - Private properties

            fileprivate var headers: Internals.Headers

            private var key: Name?
            private var values: [String]?

            init(_ headers: Internals.Headers) {
                let key = headers._first
                let values = key.flatMap {
                    headers._values($0)
                }

                self.headers = headers
                self.key = key
                self.values = values
            }

            // MARK: - Internal methods

            mutating func next() -> Element? {
                guard let key = key else {
                    return nil
                }

                if var values, !values.isEmpty {
                    let value = values.removeFirst()
                    self.values = values
                    return (key.rawValue, value)
                }

                headers._remove(key)

                self.key = headers._first
                self.values = self.key.flatMap {
                    headers._values($0)
                }

                return next()
            }
        }

        typealias Element = (name: String, value: String)

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

        // MARK: - Internal properties

        var isEmpty: Bool {
            keys.isEmpty
        }

        var count: Int {
            values.lazy.map(\.count).reduce(.zero, +)
        }

        // MARK: - Private properties

        fileprivate var _first: Name? {
            keys.first
        }

        private var keys: [Name]
        private var values: [[String]]

        // MARK: - Inits

        init() {
            self.keys = []
            self.values = []
        }

        init(_ headers: NIOHTTP1.HTTPHeaders) {
            self.init(Array(headers))
        }

        init(_ headers: [(String, String)]) {
            self.init()

            for (name, value) in headers {
                add(name: name, value: value)
            }
        }

        // MARK: - Internal methods

        func build() -> NIOHTTP1.HTTPHeaders {
            .init(Array(self))
        }

        mutating func set(name: String, value: String) {
            let name = self.name(name)
            let value = trimmingCharacters(value)

            if let index = keys.firstIndex(of: name) {
                values[index] = [value]
            } else {
                keys.append(name)
                values.append([value])
            }
        }

        mutating func add(name: String, value: String) {
            let name = self.name(name)
            let value = trimmingCharacters(value)

            if let index = keys.firstIndex(of: name) {
                values[index].append(value)
            } else {
                keys.append(name)
                values.append([value])
            }
        }

        mutating func remove(name: String) {
            _remove(self.name(name))
        }

        func contains(name: String) -> Bool {
            keys.contains(self.name(name))
        }

        func contains(_ value: String, for name: String) -> Bool {
            guard let index = keys.firstIndex(of: self.name(name)) else {
                return false
            }

            return values[index].contains(value)
        }

        func contains(name: String, where closure: (String) throws -> Bool) rethrows -> Bool {
            guard let index = keys.firstIndex(of: self.name(name)) else {
                return false
            }

            return try values[index].contains(where: closure)
        }

        subscript(_ name: String) -> [String]? {
            _values(self.name(name))
        }

        func makeIterator() -> Iterator {
            Iterator(self)
        }

        func merging(
            _ headers: Internals.Headers,
            by groupingValues: ([String], [String]) throws -> [String]
        ) rethrows -> Internals.Headers {
            var mutableSelf = self

            for _name in headers.keys {
                let name = _name.rawValue

                guard let values = headers[name] else {
                    continue
                }

                if let index = mutableSelf.keys.firstIndex(of: _name) {
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

        // MARK: - Private methods

        fileprivate mutating func _remove(_ name: Name) {
            guard let index = keys.firstIndex(of: name) else {
                return
            }

            keys.remove(at: index)
            values.remove(at: index)
        }

        fileprivate func _values(_ name: Name) -> [String]? {
            guard let index = keys.firstIndex(of: name) else {
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
}

extension Internals.Headers: RandomAccessCollection {

    struct Index: Comparable {

        let key: Int
        let value: Int

        static func < (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.key < rhs.key && lhs.value < rhs.value
        }
    }

    var startIndex: Index {
        .init(key: .zero, value: .zero)
    }

    var endIndex: Index {
        .init(key: keys.endIndex, value: values.last?.endIndex ?? values.endIndex)
    }

    subscript(position: Index) -> (name: String, value: String) {
        (
            name: keys[position.key].rawValue,
            value: values[position.key][position.value]
        )
    }

    func index(before i: Index) -> Index {
        guard values[i.key].startIndex == i.value else {
            return .init(
                key: i.key,
                value: values[i.key].index(before: i.value)
            )
        }

        let key = keys.index(before: i.key)
        return .init(
            key: key,
            value: values[key].endIndex
        )
    }

    func index(after i: Index) -> Index {
        guard values[i.key].endIndex == i.value else {
            return .init(
                key: i.key,
                value: values[i.key].index(after: i.value)
            )
        }

        let key = keys.index(after: i.key)
        return .init(
            key: key,
            value: values[key].startIndex
        )
    }
}
