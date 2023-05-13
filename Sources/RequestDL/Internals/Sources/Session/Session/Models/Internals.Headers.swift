/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOHTTP1

extension Internals {

    struct Headers: Sendable, Codable, Hashable {

        // MARK: - Internal properties

        var isEmpty: Bool {
            dictionary.isEmpty
        }

        var count: Int {
            dictionary.count
        }

        // MARK: - Private properties

        private var dictionary: [HeaderKey: [String]]

        // MARK: - Inits

        init() {
            self.dictionary = [:]
        }

        init(_ headers: NIOHTTP1.HTTPHeaders) {
            self.init(Array(headers))
        }

        init(_ headers: [(String, String)]) {
            self.init()

            for (name, value) in headers {
                addValue(value, forKey: name)
            }
        }

        // MARK: - Internal methods

        func build() -> NIOHTTP1.HTTPHeaders {
            .init(Array(self))
        }

        mutating func setValue(_ value: String, forKey key: String) {
            self[key] = splitHeaderValues(value)
        }

        mutating func addValue(_ value: String, forKey key: String) {
            var array = self[key] ?? []
            array.append(contentsOf: splitHeaderValues(value))
            self[key] = array
        }

        func getValue(forKey key: String) -> String? {
            self[key]?.joined(separator: "; ")
        }

        func contains(_ value: String, forKey key: String) -> Bool {
            self[key]?.first(where: {
                $0.range(of: value, options: .caseInsensitive) != nil
            }) != nil
        }

        func makeIterator() -> Iterator {
            Iterator(dictionary: dictionary.map {
                ($0.rawValue, $1.joined(separator: "; "))
            })
        }

        // MARK: - Private methods

        fileprivate subscript(_ key: String) -> [String]? {
            get { dictionary[.init(key)] }
            set { dictionary[.init(key)] = newValue }
        }

        private func splitHeaderValues(_ value: String) -> [String] {
            value
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
}

extension Internals.Headers: Sequence {

    typealias Element = (String, String)

    struct Iterator: IteratorProtocol {

        // MARK: - Private properties

        fileprivate var dictionary: [Element]

        // MARK: - Internal methods

        mutating func next() -> Element? {
            guard dictionary.first != nil else {
                return nil
            }

            return dictionary.removeFirst()
        }
    }
}

private extension Internals.Headers {

    struct HeaderKey: Sendable, Hashable, Codable {

        // MARK: - Internal properties

        let rawValue: String

        // MARK: - Private properties

        private var hash: Int

        // MARK: - Inits

        init(_ rawValue: String) {
            self.rawValue = rawValue
            self.hash = rawValue.lowercased().hashValue
        }

        // MARK: - Internal static methods

        static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.hash == rhs.hash
        }

        // MARK: - Internal methods

        func hash(into hasher: inout Hasher) {
            hash.hash(into: &hasher)
        }
    }
}
