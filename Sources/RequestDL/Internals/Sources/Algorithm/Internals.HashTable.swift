/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct HashTable<Key: Hashable & Sendable, Value: Sendable>: Sendable {

        private typealias Element = (key: Key, value: Value)

        // MARK: - Internal properties

        private(set) var count = 0

        // MARK: - Private properties

        private var capacity: Int {
            return buckets.count
        }

        private var buckets: [Array<Element>?]

        // MARK: - Inits

        init(capacity: Int = 16) {
            buckets = Array(repeating: nil, count: capacity)
        }

        // MARK: - Public methods

        subscript(_ key: Key) -> Value? {
            get { get(key) }
            set {
                if let newValue {
                    set(newValue, forKey: key)
                } else {
                    remove(key)
                }
            }
        }

        // MARK: - Private methods

        private mutating func set(_ value: Value, forKey key: Key) {
            let index = self.index(forKey: key)
            var bucket = buckets[index] ?? []

            for i in 0..<bucket.count {
                if bucket[i].key == key {
                    bucket[i].value = value
                    buckets[index] = bucket
                    return
                }
            }

            bucket.append((key: key, value: value))
            buckets[index] = bucket
            count += 1

            if Double(count) / Double(capacity) > 0.75 {
                resize()
            }
        }

        private func get(_ key: Key) -> Value? {
            let index = self.index(forKey: key)
            guard let bucket = buckets[index] else { return nil }

            for element in bucket {
                if element.key == key {
                    return element.value
                }
            }
            return nil
        }

        @discardableResult
        private mutating func remove(_ key: Key) -> Value? {
            let index = self.index(forKey: key)
            guard var bucket = buckets[index] else { return nil }

            for i in 0..<bucket.count {
                if bucket[i].key == key {
                    let element = bucket.remove(at: i)
                    buckets[index] = bucket.isEmpty ? nil : bucket
                    count -= 1
                    return element.value
                }
            }
            return nil
        }

        private mutating func resize() {
            let oldBuckets = buckets
            let newCapacity = capacity * 2
            buckets = Array(repeating: nil, count: newCapacity)
            count = 0

            for bucket in oldBuckets {
                if let bucket = bucket {
                    for element in bucket {
                        set(element.value, forKey: element.key)
                    }
                }
            }
        }

        private func index(forKey key: Key) -> Int {
            return abs(key.hashValue) % capacity
        }
    }
}
