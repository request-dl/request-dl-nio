/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    final class Storage: @unchecked Sendable {

        // MARK: - Internal static properties

        static let lifetime: UInt64 = 5_000_000_000 * 60
        static let shared = Storage(lifetime: lifetime)

        // MARK: - Private properties

        private let lock = Lock()
        private let lifetime: UInt64

        // MARK: - Unsafe properties

        private var _table = [AnyHashable: Register]()

        // MARK: - Inits

        init(lifetime: UInt64) {
            self.lifetime = lifetime
            scheduleCleanup()
        }

        // MARK: - Internal methods

        func setValue<Value: Sendable>(_ value: Value?, forKey key: AnyHashable) {
            lock.withLockVoid {
                _table[key] = value.map {
                    .init(value: $0)
                }
            }
        }

        func getValue<Value: Sendable>(_ type: Value.Type, forKey key: AnyHashable) -> Value? {
            lock.withLock {
                guard let value = _table[key]?.value as? Value else {
                    return nil
                }

                _table[key] = .init(value: value)
                return value
            }
        }

        // MARK: - Private properties

        private func scheduleCleanup() {
            _Concurrency.Task(priority: .background) {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime))
                cleanupIfNeeded()
                scheduleCleanup()
            }
        }

        private func cleanupIfNeeded() {
            lock.withLockVoid {
                let now = Date()
                let lifetime = Double(lifetime) / 1_000_000_000

                _table = _table.filter {
                    $1.readAt.distance(to: now) <= lifetime
                }
            }
        }
    }
}

extension Internals.Storage {

    fileprivate struct Register: Sendable {
        let readAt = Date()
        let value: Sendable
    }
}
