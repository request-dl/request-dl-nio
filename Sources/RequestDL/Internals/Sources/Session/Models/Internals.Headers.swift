/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOHTTP1

extension Internals {
    struct Headers: Sendable {

        private var dictionary: [HeaderKey: String]

        init() {
            self.dictionary = [:]
        }

        init(_ headers: HTTPHeaders) {
            self.init(Array(headers))
        }

        init(_ headers: [(String, String)]) {
            self.init()

            for (name, value) in headers {
                self[name] = value
            }
        }

        private subscript(_ key: String, appending: Bool) -> String? {
            get { dictionary[.init(key)] }

            set {
                let key = HeaderKey(key)

                if appending, let value = dictionary[key] {
                    dictionary[key] = newValue.map {
                        value + "; \($0)"
                    }
                } else {
                    dictionary[key] = newValue
                }
            }
        }

        private(set) subscript(_ key: String) -> String? {
            get { self[key, false] }
            set {
                self[key, false] = newValue
            }
        }

        mutating func setValue(_ value: String, forKey key: String) {
            self[key] = value
        }

        mutating func addValue(_ value: String, forKey key: String) {
            self[key, true] = value
        }

        func getValue(forKey key: String) -> String? {
            self[key]
        }

        func build() -> HTTPHeaders {
            .init(Array(self))
        }
    }
}

extension Internals.Headers: Sequence {

    typealias Element = (String, String)

    struct Iterator: IteratorProtocol {
        fileprivate var dictionary: [Element]

        mutating func next() -> Element? {
            guard dictionary.first != nil else {
                return nil
            }

            return dictionary.removeFirst()
        }
    }

    func makeIterator() -> Iterator {
        Iterator(dictionary: dictionary.map {
            ($0.rawValue, $1)
        })
    }
}

extension Internals.Headers {

    var isEmpty: Bool {
        dictionary.isEmpty
    }

    var count: Int {
        dictionary.count
    }
}

private extension Internals.Headers {

    struct HeaderKey: Hashable {

        let rawValue: String
        private var hash: Int

        init(_ rawValue: String) {
            self.rawValue = rawValue
            self.hash = rawValue.lowercased().hashValue
        }

        static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.hash == rhs.hash
        }

        func hash(into hasher: inout Hasher) {
            hash.hash(into: &hasher)
        }
    }
}

extension Internals.Headers: Equatable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.dictionary == rhs.dictionary
    }
}

extension Internals.Headers: Hashable {

    func hash(into hasher: inout Hasher) {
        dictionary.hash(into: &hasher)
    }
}
