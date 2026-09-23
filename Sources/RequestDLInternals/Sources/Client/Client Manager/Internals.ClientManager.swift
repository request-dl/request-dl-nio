//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#if canImport(Darwin)
import struct Foundation.DispatchTime
#endif
#endif

extension Internals {

    package final class ClientManager: @unchecked Sendable {

        // MARK: - Internal static properties

        /// Nanoseconds, matching `UnitTime.nanoseconds` (same convention as `Internals.Timeout`/
        /// `Internals.ConnectionPool`). Kept portable rather than `NIOCore.TimeAmount`: this class
        /// caches `.urlSession` clients too, so its own lifetime bookkeeping shouldn't need NIO
        /// to exist at all.
        package static let lifetime: Int64 = 5 * 60 * 1_000_000_000

        /// A ceiling on how many pooled clients `_table` may hold in total, across every key.
        ///
        /// Age is the intended eviction policy, same as `Internals.Storage.maximumCount`, and
        /// this exists for the same reason: so a workload that keeps producing configurations
        /// which can never match a pooled one cannot grow the table without bound. Set far lower
        /// than `Storage`'s, since an entry here is a whole HTTP client with its own connection
        /// pool rather than a single cached value.
        package static let maximumCount = 64

        package static let shared = ClientManager(lifetime: lifetime)

        // MARK: - Private static properties

        /// Flags a `client(provider:sessionConfiguration:)` or `cleanupIfNeeded()` that is still
        /// running after 45s. Set higher than the other `AsyncLock`s in `Internals`:
        /// `cleanupIfNeeded()` shares this lock and can shut down several expired clients in one
        /// sweep, each a real network drain — concurrently, so the sweep costs the longest of
        /// them rather than their sum, but a wide margin is still needed to avoid flagging a
        /// legitimately busy one. Development builds only. See `AsyncLock.Watchdog`.
        #if DEBUG
        private static let watchdog: AsyncLock.Watchdog? = .init(seconds: 45) {
            Internals.assertionFailure($0)
        }
        #else
        private static let watchdog: AsyncLock.Watchdog? = nil
        #endif

        // MARK: - Private properties

        // Not `private`: `Internals.ClientManager+NIO.swift`'s extension (a different file, the
        // `.nio`/`.nioTransportServices` half of this class) reaches these too. `internal`
        // (the default) is as narrow as a member can be while still being visible there. Swift
        // has no "private to this type across files" access level.
        let lock = AsyncLock(watchdog: watchdog)
        private let lifetime: Int64

        // Not `private`, same cross-file reason as ``lock``/``tableLock``/``_table``.
        let maximumCount: Int

        let tableLock = Lock()

        // MARK: - Internal properties

        /// How many clients are pooled in total, across every key. Bookkeeping only; nothing in
        /// the resolution path reads it.
        package var count: Int {
            tableLock.withLock { _table.values.reduce(0) { $0 + $1.count } }
        }

        // MARK: - Unsafe properties

        var _table = [String: [Item]]()

        // MARK: - Inits

        package init(lifetime: Int64, maximumCount: Int = ClientManager.maximumCount) {
            precondition(maximumCount >= 1, "ClientManager needs room for at least one client")

            self.lifetime = lifetime
            self.maximumCount = maximumCount

            scheduleCleanup()
        }

        // MARK: - Internals methods

        /// Executor-aware counterpart to `client(provider:sessionConfiguration:)`: resolves
        /// `sessionConfiguration.resolveExecutor()` and actually builds/caches the client that
        /// decision points to, rather than only deciding in the abstract. Covers both axes:
        /// `.urlSession` vs. not, and, within the `.nio` branch, plain NIO vs.
        /// NIOTransportServices, so `preferredExecutor(.nioTransportServices)`/
        /// `requiredExecutor(.nioTransportServices)` actually decide which event loop group a real
        /// request gets, not just `enableNetworkFramework`.
        ///
        /// Shares this manager's own `_table` with `Internals.ClientManager+NIO.swift`'s
        /// NIO-only `client(provider:sessionConfiguration:)`: a `.urlSession` entry is keyed
        /// apart from a `.nio`/NIOTransportServices one for
        /// the same provider (see `_createNewURLSessionClient`'s `id`), so the two can never
        /// collide or be handed back for each other.
        ///
        /// Likewise, `_nioClient`'s own `isCompatibleWithNetworkFramework`
        /// parameter, not `sessionConfiguration.isCompatibleWithNetworkFramework`, is what
        /// keys a NIOTransportServices entry apart from a plain-NIO one here
        /// (`SessionProvider.uniqueIdentifier(with:)`'s `"NTW."` prefix reads that parameter, not
        /// `enableNetworkFramework` directly), so an executor-resolved and a flag-resolved client
        /// for the same provider can only ever collide if they'd have made the identical choice
        /// anyway.
        package func resolvedClient(
            provider: SessionProvider,
            sessionConfiguration: Internals.Session.Configuration
        ) async throws -> Internals.ClientManager.Client {
            #if canImport(NIOCore)
            #if canImport(Darwin)
            let executor = sessionConfiguration.resolveExecutor()

            guard executor == .urlSession else {
                return .nio(
                    try await _nioClient(
                        provider: provider,
                        sessionConfiguration: sessionConfiguration,
                        isCompatibleWithNetworkFramework: executor == .nioTransportServices
                    )
                )
            }
            #else
            // Off Darwin, `resolveExecutor()` never resolves to `.urlSession` (see its own
            // implementation), so NIOCore being available here means `.nio` unconditionally.
            return .nio(try await client(provider: provider, sessionConfiguration: sessionConfiguration))
            #endif
            #endif

            #if canImport(Darwin)
            let sessionProviderID =
                "URLSession."
                + provider.uniqueIdentifier(
                    with: SessionProviderOptions(isCompatibleWithNetworkFramework: false)
                )

            return try await lock.withLock {
                try Task.checkCancellation()

                if sessionConfiguration.isPoolable,
                    let item = tableLock.withLock({
                        _reusableItem(id: sessionProviderID, sessionConfiguration: sessionConfiguration)
                    }),
                    case .urlSession = item
                {
                    return item
                }

                return .urlSession(
                    try await _createNewURLSessionClient(
                        id: sessionProviderID,
                        sessionConfiguration: sessionConfiguration
                    )
                )
            }
            #endif
        }

        // MARK: - Private methods

        private func scheduleCleanup() {
            _Concurrency.Task.detached(priority: .utility) { [weak self, lifetime] in
                while true {
                    do {
                        try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime))
                    } catch {
                        // Sleeping fails on cancellation and nothing else. Yielding and looping
                        // meant the next sleep failed immediately too, turning this into a
                        // tight loop that never slept again and never stopped.
                        return
                    }

                    guard let self else {
                        return
                    }

                    await cleanupIfNeeded()
                }
            }
        }

        /// Monotonic, not wall clock. `Date` moves when the user or NTP moves the system clock:
        /// backwards and no client is ever recycled, forwards and every client is eligible at
        /// once, including one handed out a moment ago and about to be used.
        #if canImport(Darwin)
        static func monotonicNow() -> UInt64 {
            DispatchTime.now().uptimeNanoseconds
        }

        func isExpired(_ item: Item, at now: UInt64) -> Bool {
            now - item.readAt > lifetime
        }
        #else
        static func monotonicNow() -> ContinuousClock.Instant {
            ContinuousClock.now
        }

        func isExpired(_ item: Item, at now: ContinuousClock.Instant) -> Bool {
            item.readAt.duration(to: now) > .nanoseconds(lifetime)
        }
        #endif

        /// Whether dropping the last reference to `client` retires it on its own.
        ///
        /// `.nio` does: `Internals.Client.deinit` shuts its `HTTPClient` down. `.urlSession` does
        /// not — `URLSession` retains its delegate, so the client is never released — and has to
        /// be invalidated explicitly. See `_evictIfNeeded(protecting:)` for what that difference
        /// decides.
        static func retiresOnRelease(_ client: Internals.ClientManager.Client) -> Bool {
            switch client {
            #if canImport(NIOCore)
            case .nio:
                return true
            #endif
            #if canImport(Darwin)
            case .urlSession:
                return false
            #endif
            }
        }

        /// Retires every client that has been idle for longer than `lifetime`.
        ///
        /// Decides first, shuts down after. The two used to be interleaved, one `await` per
        /// expired client, all of it inside `lock` — which every client resolution in the process
        /// also has to take. A sweep over a large accumulated backlog therefore stalled every
        /// request that happened to need a client while it ran, for the sum of every drain rather
        /// than the longest one.
        private func cleanupIfNeeded() async {
            await lock.withLock {
                let now = Self.monotonicNow()

                var expired = [(key: String, item: Item)]()

                tableLock.withLock {
                    for (key, items) in _table {
                        var surviving = [Item]()

                        for item in items {
                            if item.client.isRunning {
                                surviving.append(item.updatingReadAt())
                                continue
                            }

                            if isExpired(item, at: now) {
                                expired.append((key, item))
                            } else {
                                surviving.append(item)
                            }
                        }

                        _table[key] = surviving.isEmpty ? nil : surviving
                    }
                }

                guard !expired.isEmpty else {
                    return
                }

                let failed = await withTaskGroup(of: (String, Item)?.self) { group in
                    for (key, item) in expired {
                        group.addTask {
                            (try? await item.client.shutdown()) == true ? nil : (key, item)
                        }
                    }

                    var failed = [(String, Item)]()

                    for await result in group {
                        if let result {
                            failed.append(result)
                        }
                    }

                    return failed
                }

                // A client that refused to shut down is put back rather than dropped: it still
                // owns live resources, so losing the only reference to it would leak them. The
                // next sweep tries again.
                guard !failed.isEmpty else {
                    return
                }

                tableLock.withLock {
                    for (key, item) in failed {
                        _table[key, default: []].append(item)
                    }
                }
            }
        }

        /// Shuts `clients` down off `tableLock` and off the caller's own path.
        ///
        /// An eviction is bookkeeping the caller didn't ask for — it is in the middle of handing
        /// out a brand-new client — so it shouldn't wait on a drain, and `tableLock` is a plain
        /// mutex that must never be held across one. Concurrent within the detached task, for the
        /// same reason `cleanupIfNeeded()`'s own shutdowns are.
        static func shutdownDetached(_ clients: [Internals.ClientManager.Client]) {
            guard !clients.isEmpty else {
                return
            }

            _Concurrency.Task.detached(priority: .utility) {
                await withTaskGroup(of: Void.self) { group in
                    for client in clients {
                        group.addTask { _ = try? await client.shutdown() }
                    }
                }
            }
        }

        // MARK: - Unsafe methods

        /// - Warning: Lockless. The caller must be holding ``tableLock``.
        ///
        /// Returns the cached `Internals.ClientManager.Client` regardless of which backend it
        /// wraps: shared by both `Internals.ClientManager+NIO.swift`'s `_nioClient` (unwraps
        /// `.nio`) and `resolvedClient(provider:sessionConfiguration:)` (unwraps `.urlSession`),
        /// so the age/reuse logic below is written once rather than duplicated per backend. Not
        /// `private`, for the same cross-file reason as ``lock``/``tableLock``/``_table``.
        func _reusableItem(
            id: String,
            sessionConfiguration: Internals.Session.Configuration
        ) -> Internals.ClientManager.Client? {
            let now = {
                #if canImport(Darwin)
                DispatchTime.now().uptimeNanoseconds
                #else
                ContinuousClock.now
                #endif
            }()

            // Age checked here, not only in the sweep. The sweep runs every `lifetime` and
            // retires what is older than `lifetime`, so a client that went idle just after one
            // pass was still handed out until the next, at nearly twice its lifetime. `readAt`
            // is refreshed on every hand out, so a client in active use never ages out; only an
            // idle one does, which is the whole intent.
            guard
                var items = _table[id],
                let index = items.firstIndex(where: { item in
                    item.sessionConfiguration == sessionConfiguration
                        && {
                            #if canImport(Darwin)
                            now - item.readAt <= lifetime
                            #else
                            item.readAt.duration(to: .now) <= .nanoseconds(lifetime)
                            #endif
                        }()
                })
            else { return nil }

            let item = items[index]

            items[index] = item.updatingReadAt()
            _table[id] = items

            return item.client
        }

        /// - Warning: Lockless. The caller must be holding ``tableLock``.
        ///
        /// Brings `_table` back under ``maximumCount``, oldest first, dropping to three quarters
        /// of it in one pass so a table sitting exactly at the ceiling doesn't evict on every
        /// single insert that follows. Same shape as `Internals.Storage._evictIfNeeded()`, except
        /// that what is evicted here owns a connection pool, so it has to be shut down rather
        /// than merely forgotten.
        ///
        /// The ceiling never gates service. Only clients with nothing in flight are candidates,
        /// and a caller is never made to wait for one to free up or turned away because there is
        /// nothing to evict: a table whose every entry is mid-request simply overshoots, and the
        /// `lifetime` sweep and the next insert with something idle in it bring it back down. The
        /// alternative — delaying a request, or tearing connections down out from under live ones
        /// — trades a caller's latency for a bookkeeping limit, which is the wrong way round.
        ///
        /// Evicting a `.nio` client is only ever *un-caching*, never shutting down.
        /// `Internals.Client.deinit` retires it once the last reference goes, so a caller that
        /// was handed one and has not started its request yet — where `isRunning` is still
        /// `false` — keeps it alive by holding it. Shutting it down here instead raced exactly
        /// that gap, and a 200-session burst hit it (`HTTPClientError.alreadyShutdown`).
        ///
        /// `.urlSession` has no such fallback (`URLSession` retains its delegate, so the client
        /// is never released on its own) and so has to be invalidated explicitly. That cannot be
        /// made race free the same way, so an entry is only evicted *with* a shutdown once it is
        /// already past `lifetime` — i.e. only when the periodic sweep would have retired it
        /// anyway. The ceiling brings that forward; it never retires anything the sweep wouldn't.
        ///
        /// - Parameter protecting: The client the caller is in the middle of handing out. It is
        /// idle by definition (nothing has been asked of it yet) and its entry is the newest in
        /// the table, so without this it is the *first* thing an at-capacity insert evicts — and
        /// since the table is also what owns a client's lifetime, evicting it would shut down the
        /// very client being returned.
        ///
        /// - Returns: The evicted clients that need an explicit shutdown, which the caller must
        ///   hand to ``shutdownDetached(_:)``. Returning them rather than shutting them down here
        ///   is what keeps a network drain off ``tableLock``.
        func _evictIfNeeded(
            protecting protectedClient: Internals.ClientManager.Client? = nil
        ) -> [Internals.ClientManager.Client] {
            let count = _table.values.reduce(0) { $0 + $1.count }

            guard count > maximumCount else {
                return []
            }

            let target = max(maximumCount - (maximumCount / 4), 1)
            let protectedIdentifier = protectedClient?.objectIdentifier
            let now = Self.monotonicNow()

            let evictable =
                _table
                .flatMap { key, items in
                    items.enumerated().map { (key: key, offset: $0.offset, item: $0.element) }
                }
                .filter {
                    guard
                        !$0.item.client.isRunning,
                        $0.item.client.objectIdentifier != protectedIdentifier
                    else {
                        return false
                    }

                    return Self.retiresOnRelease($0.item.client) || isExpired($0.item, at: now)
                }
                .sorted { $0.item.readAt < $1.item.readAt }
                .prefix(count - target)

            var offsetsByKey = [String: [Int]]()

            for entry in evictable {
                offsetsByKey[entry.key, default: []].append(entry.offset)
            }

            for (key, offsets) in offsetsByKey {
                guard var items = _table[key] else {
                    continue
                }

                // Descending, so removing one doesn't shift the offsets still to be removed.
                for offset in offsets.sorted(by: >) {
                    items.remove(at: offset)
                }

                _table[key] = items.isEmpty ? nil : items
            }

            // Only what cannot retire itself. Handing a `.nio` client here would reintroduce
            // exactly the race this method's doc describes.
            return evictable.map(\.item.client).filter { !Self.retiresOnRelease($0) }
        }

        #if canImport(Darwin)
        /// - Warning: Lockless with respect to ``tableLock``, which it takes itself.
        ///
        /// `id` is expected to already carry `resolvedClient(provider:sessionConfiguration:)`'s
        /// `"URLSession."` prefix, keeping this entry apart from any `.nio` one the same provider
        /// might also have cached under its bare (or `"NTW."`-prefixed) id.
        ///
        /// `Internals.URLSessionClient.init` is routed through `Internals.FileSystemManager.run`
        /// rather than called directly: it reads the certificate/private-key files a
        /// `SecureConnection` names (`Internals.Certificate.resolvedDERBytes()`, portable and
        /// NIOSSL-backed alike) and, for mTLS, makes synchronous Keychain calls
        /// (`Internals.RawBytesIdentityBuilder`/`Internals.IdentityManager`), none of which are
        /// `async`, since Keychain's own API isn't. Calling it inline here would block whichever
        /// Swift Concurrency cooperative thread reached this cache miss for as long as that takes;
        /// `FileSystemManager.run` is the same escape hatch every other blocking file operation in
        /// `Internals` already uses for exactly that reason (see its own doc comment).
        private func _createNewURLSessionClient(
            id: String,
            sessionConfiguration: Internals.Session.Configuration
        ) async throws -> Internals.URLSessionClient {
            let client = try await Internals.FileSystemManager.run {
                try Internals.URLSessionClient(
                    configuration: sessionConfiguration.buildURLSessionConfiguration(),
                    secureConnection: sessionConfiguration.secureConnection,
                    redirectConfiguration: sessionConfiguration.redirectConfiguration
                        ?? .follow(max: 5, allowCycles: false),
                    proxy: sessionConfiguration.proxy,
                    maximumConcurrentConnections: sessionConfiguration.maximumConcurrentConnections
                )
            }

            // Still pooled even when `!sessionConfiguration.isPoolable`, same as the `.nio` side:
            // this table is what owns a client's lifetime, not merely a reuse cache. Doubly so
            // here, since an `Internals.URLSessionClient` has no `deinit` fallback to shut itself
            // down — `URLSession` retains its delegate, so the client is never released on its
            // own — which makes this table the only thing that ever gets around to invalidating
            // it. An entry nobody can reuse is still worth keeping for the sweep to find;
            // `_evictIfNeeded` is what keeps that from growing without bound.
            let evicted = tableLock.withLock {
                var items = _table[id] ?? []

                items.append(
                    .createNew(
                        sessionConfiguration: sessionConfiguration,
                        client: .urlSession(client)
                    )
                )

                _table[id] = items

                return _evictIfNeeded(protecting: .urlSession(client))
            }

            Self.shutdownDetached(evicted)

            return client
        }
        #endif
    }
}
