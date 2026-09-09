//
// See LICENSE for this package's licensing information.
//

import NIOCore
import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
#if canImport(Darwin)
import struct Foundation.DispatchTime
#endif
import class Foundation.ProcessInfo
#endif

#if DEBUG
/// TEMP DIAGNOSTIC (remove after investigation): traces `Internals.Storage` cache hits/misses
/// to chase an intermittent `StoredObject`-identity flake in `PropertyReaderTests`. Silent
/// unless `REQUESTDL_STORAGE_DEBUG` is set in the environment, and compiled out entirely in
/// release builds.
private let isStorageDebugLoggingEnabled = ProcessInfo.processInfo.environment["REQUESTDL_STORAGE_DEBUG"] != nil

private func storageDebugLog(_ message: @autoclosure () -> String) {
    guard isStorageDebugLoggingEnabled else {
        return
    }

    print(message())
}
#endif

extension Internals {

    package final class Storage: @unchecked Sendable {

        private struct Register: Sendable {

            #if canImport(Darwin)
            // Monotonic, not wall clock. `Date` moves when the user or NTP moves the system
            // clock: backwards and nothing ever expires, forwards and the whole table does at
            // once. The trade is that this does not advance while the device is suspended,
            // which for a cache lifetime is the harmless direction.
            package let readAt = DispatchTime.now().uptimeNanoseconds
            #else
            package let readAt = ContinuousClock.now
            #endif
            package let value: any Sendable
        }

        // MARK: - Internal static properties

        package static let lifetime = TimeAmount.seconds(5 * 60)

        /// A ceiling, not a working limit.
        ///
        /// Age is the intended eviction policy, and this exists so a workload that touches a
        /// great many distinct keys inside one lifetime cannot grow the table without bound.
        /// It is set well above what normal use reaches, so that hitting it means something
        /// unusual is happening rather than that the cache is too small.
        package static let maximumCount = 256

        package static let shared = Storage(lifetime: lifetime)

        // MARK: - Internal properties

        package var count: Int {
            lock.withLock { _table.count }
        }

        // MARK: - Private properties

        private let lock = Lock()
        private let lifetime: TimeAmount
        private let maximumCount: Int

        // MARK: - Unsafe properties

        private var _table = [AnyHashable: Register]()

        // MARK: - Inits

        package init(lifetime: TimeAmount, maximumCount: Int = Storage.maximumCount) {
            precondition(maximumCount >= 1, "Storage needs room for at least one entry")

            self.lifetime = lifetime
            self.maximumCount = maximumCount

            scheduleCleanup()
        }

        // MARK: - Internal methods

        package func setValue<Value: Sendable>(_ value: Value?, forKey key: AnyHashable) {
            lock.withLockVoid {
                _table[key] = value.map {
                    .init(value: $0)
                }

                _evictIfNeeded()
            }
        }

        package func getValue<Value: Sendable>(_ type: Value.Type, forKey key: AnyHashable) -> Value? {
            lock.withLock { () -> Value? in
                guard let register = _table[key] else {
                    return nil
                }

                let isValid = {
                    #if canImport(Darwin)
                    DispatchTime.now().uptimeNanoseconds - register.readAt <= lifetime.nanoseconds
                    #else
                    register.readAt.duration(to: .now) <= .nanoseconds(lifetime.nanoseconds)
                    #endif
                }()
                // Age checked here, not only in the sweep. The sweep runs every `lifetime` and
                // removes what is older than `lifetime`, so an entry that went idle just after
                // one pass survived until the next and could be handed out at nearly twice its
                // lifetime. That made the sweep interval a correctness parameter; it should
                // only be a memory one.
                guard isValid else {
                    #if DEBUG
                    storageDebugLog("[Internals.Storage DEBUG] EXPIRE ttl key=\(key) tableCount=\(_table.count)")
                    #endif
                    _table[key] = nil
                    return nil
                }

                guard let value = register.value as? Value else {
                    #if DEBUG
                    storageDebugLog("[Internals.Storage DEBUG] TYPE MISMATCH key=\(key) tableCount=\(_table.count)")
                    #endif
                    return nil
                }

                // Reinserting refreshes the timestamp, so reading keeps an entry alive and
                // moves it away from the front of the eviction queue.
                _table[key] = .init(value: value)
                return value
            }
        }

        /// Stores `value` only when `key` is free, and returns whatever ends up stored.
        ///
        /// Exists because reading, deciding and writing through the two calls above is a
        /// check then act: two callers can both miss, both build a value, and both store one,
        /// which is exactly what a memoised object must never do. Here the decision and the
        /// write are one critical section, so at most one value is ever handed out.
        ///
        /// The value is built by the caller, outside the lock, on purpose. Running a caller
        /// supplied factory inside would deadlock the moment it touched this storage again,
        /// and the lock is not reentrant. The price is that a loser may build a value that is
        /// immediately discarded.
        package func setValueIfAbsent<Value: Sendable>(_ value: Value, forKey key: AnyHashable) -> Value {
            lock.withLock {
                if let existing = _table[key]?.value as? Value {
                    // Same refresh a read would do.
                    _table[key] = .init(value: existing)
                    return existing
                }

                #if DEBUG
                storageDebugLog("[Internals.Storage DEBUG] CREATE key=\(key) tableCount=\(_table.count + 1)")
                #endif

                _table[key] = .init(value: value)
                _evictIfNeeded()

                return value
            }
        }

        // MARK: - Private methods

        private func scheduleCleanup() {
            _Concurrency.Task.detached(priority: .utility) { [weak self, lifetime] in
                while true {
                    do {
                        try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime.nanoseconds))
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
                let now = {
                    #if canImport(Darwin)
                    DispatchTime.now().uptimeNanoseconds
                    #else
                    ContinuousClock.now
                    #endif
                }()

                _table = _table.filter {
                    #if canImport(Darwin)
                    now - $1.readAt <= lifetime.nanoseconds
                    #else
                    $1.readAt.duration(to: .now) <= .nanoseconds(lifetime.nanoseconds)
                    #endif
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

            let oldest =
                _table
                .sorted { $0.value.readAt < $1.value.readAt }
                .prefix(excess)

            for (key, _) in oldest {
                #if DEBUG
                storageDebugLog("[Internals.Storage DEBUG] EVICT capacity key=\(key) tableCountBefore=\(_table.count)")
                #endif
                _table[key] = nil
            }
        }
    }
}
