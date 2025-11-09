/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct HashTable<Key: Hashable & Sendable, Value: Sendable>: Sendable {

        private typealias Element = (key: Key, value: Value)

        // MARK: - Internal properties

        var count: Int {
            lock.withLock { _count }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _count = 0

        private var _capacity: Int {
            _buckets.count
        }

        private var _buckets: [Array<Element>?]
        // MARK: - Inits

        init(capacity: Int = 16) {
            _buckets = Array(repeating: nil, count: capacity)
        }

        // MARK: - Public methods

        subscript(_ key: Key) -> Value? {
            get {
                lock.withLock {
                    _get(key)
                }
            }
            set {
                lock.withLock {
                    if let newValue {
                        _set(newValue, forKey: key)
                    } else {
                        _remove(key)
                    }
                }
            }
        }

        // MARK: - Unsafe methods

        private mutating func _set(_ value: Value, forKey key: Key) {
            let index = _index(forKey: key)
            var bucket = _buckets[index] ?? []

            for i in 0..<bucket.count {
                if bucket[i].key == key {
                    bucket[i].value = value
                    _buckets[index] = bucket
                    return
                }
            }

            bucket.append((key: key, value: value))
            _buckets[index] = bucket
            _count += 1

            if Double(_count) / Double(_capacity) > 0.75 {
                _resize()
            }
        }

        private func _get(_ key: Key) -> Value? {
            let index = _index(forKey: key)
            guard let bucket = _buckets[index] else { return nil }

            for element in bucket {
                if element.key == key {
                    return element.value
                }
            }
            return nil
        }

        @discardableResult
        private mutating func _remove(_ key: Key) -> Value? {
            let index = _index(forKey: key)
            guard var bucket = _buckets[index] else { return nil }

            for i in 0..<bucket.count {
                if bucket[i].key == key {
                    let element = bucket.remove(at: i)
                    _buckets[index] = bucket.isEmpty ? nil : bucket
                    _count -= 1
                    return element.value
                }
            }
            return nil
        }

        private mutating func _resize() {
            let oldBuckets = _buckets
            let newCapacity = _capacity * 2
            _buckets = Array(repeating: nil, count: newCapacity)
            _count = 0

            for bucket in oldBuckets {
                if let bucket = bucket {
                    for element in bucket {
                        _set(element.value, forKey: element.key)
                    }
                }
            }
        }

        private func _index(forKey key: Key) -> Int {
            return abs(key.hashValue) % _capacity
        }
    }
}
