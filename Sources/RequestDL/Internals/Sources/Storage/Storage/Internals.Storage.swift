/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif
import Dispatch
import SwiftAsyncStream

extension Internals {

    final class Storage: @unchecked Sendable {

        private struct Register: Sendable {

            // Monotonic, not wall clock. `Date` moves when the user or NTP moves the system
            // clock: backwards and nothing ever expires, forwards and the whole table does at
            // once. The trade is that this does not advance while the device is suspended,
            // which for a cache lifetime is the harmless direction.
            let readAt = DispatchTime.now().uptimeNanoseconds
            let value: any Sendable
        }

        // MARK: - Internal static properties

        static let lifetime: UInt64 = 5 * 60 * NSEC_PER_SEC

        /// A ceiling, not a working limit.
        ///
        /// Age is the intended eviction policy, and this exists so a workload that touches a
        /// great many distinct keys inside one lifetime cannot grow the table without bound.
        /// It is set well above what normal use reaches, so that hitting it means something
        /// unusual is happening rather than that the cache is too small.
        static let maximumCount = 256

        static let shared = Storage(lifetime: lifetime)

        // MARK: - Internal properties

        var count: Int {
            lock.withLock { _table.count }
        }

        // MARK: - Private properties

        private let lock = Lock()
        private let lifetime: UInt64
        private let maximumCount: Int

        // MARK: - Unsafe properties

        private var _table = [AnyHashable: Register]()

        // MARK: - Inits

        init(lifetime: UInt64, maximumCount: Int = Storage.maximumCount) {
            precondition(maximumCount >= 1, "Storage needs room for at least one entry")

            self.lifetime = lifetime
            self.maximumCount = maximumCount

            scheduleCleanup()
        }

        // MARK: - Internal methods

        func setValue<Value: Sendable>(_ value: Value?, forKey key: AnyHashable) {
            lock.withLockVoid {
                _table[key] = value.map {
                    .init(value: $0)
                }

                _evictIfNeeded()
            }
        }

        func getValue<Value: Sendable>(_ type: Value.Type, forKey key: AnyHashable) -> Value? {
            lock.withLock {
                guard let value = _table[key]?.value as? Value else {
                    return nil
                }

                // Reinserting refreshes the timestamp, so reading keeps an entry alive and
                // moves it away from the front of the eviction queue.
                _table[key] = .init(value: value)
                return value
            }
        }

        // MARK: - Private methods

        private func scheduleCleanup() {
            _Concurrency.Task.detached(priority: .utility) { [weak self, lifetime] in
                while true {
                    do {
                        try await _Concurrency.Task.sleep(nanoseconds: lifetime)
                    } catch {
                        // Sleeping fails on cancellation and nothing else. Yielding and looping
                        // meant the next sleep failed immediately too, turning this into a
                        // tight loop that never slept again and never stopped.
                        return
                    }

                    guard let self else {
                        return
                    }

                    cleanupIfNeeded()
                }
            }
        }

        private func cleanupIfNeeded() {
            lock.withLockVoid {
                let now = DispatchTime.now().uptimeNanoseconds

                _table = _table.filter {
                    now - $1.readAt <= lifetime
                }

                _evictIfNeeded()
            }
        }

        // MARK: - Unsafe methods

        /// Brings the table back under the ceiling, oldest first.
        ///
        /// Drops down to three quarters rather than removing one entry per insert. Sorting is
        /// linearithmic, so evicting one at a time would make a table sitting at the ceiling
        /// pay a full scan on every single write; in batches the cost is spread across the
        /// inserts that follow.
        ///
        /// Sorting by `readAt` also means anything already past its lifetime goes first, so
        /// this only reaches live entries once the expired ones are gone.
        ///
        /// - Warning: Lockless. The caller must be holding ``lock``.
        private func _evictIfNeeded() {
            guard _table.count > maximumCount else {
                return
            }

            let target = max(maximumCount - (maximumCount / 4), 1)
            let excess = _table.count - target

            let oldest = _table
                .sorted { $0.value.readAt < $1.value.readAt }
                .prefix(excess)

            for (key, _) in oldest {
                _table[key] = nil
            }
        }
    }
}
