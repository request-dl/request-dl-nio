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

        /// Flags a `client(provider:sessionConfiguration:)` that is still running after 45s. Set higher than the other `AsyncLock`s in `Internals`: a client
        /// resolution can build an HTTP client, read a TLS identity off disk and, for mTLS, build the
        /// identity (parsing a certificate and a private key), so a wide margin is needed to avoid flagging a legitimately
        /// busy one. Development builds only. See `AsyncLock.Watchdog`.
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

        /// How many sessions' limits are tracked, dead entries not yet removed included. Bookkeeping
        /// only, like ``count``.
        package var throttleCount: Int {
            tableLock.withLock { _throttles.count }
        }

        // MARK: - Unsafe properties

        var _table = [String: [Item]]()

        /// The semaphores that make `maximumConcurrentConnections` a limit of the session, one per
        /// session provider and limit. See ``throttledExecutor(provider:maximumConcurrentConnections:)``.
        ///
        /// Weak, and that is the whole lifecycle: a semaphore is held by the throttle of every
        /// client that uses it, and by the closure of every slot handed out and by every waiter
        /// queued behind it, so it is alive for exactly as long as the session has a live client, a
        /// request holding a slot or one waiting for it. Nothing else keeps one, so the table can
        /// neither keep a session's limit alive after the session is gone nor lose it while the
        /// session is still using it. What stays behind is the dead entry, dropped by
        /// ``removeDeadThrottles()``. Guarded by ``tableLock``.
        var _throttles = [ThrottleKey: WeakSemaphore]()

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

            // A configuration that can never be pooled has nothing to look up in the table and
            // nothing to add to it, so there is nothing for ``lock`` to order. Building its client
            // under it would only make every other session wait for the `URLSession` (and, for mTLS,
            // the identity) of this one.
            guard sessionConfiguration.isPoolable else {
                try Task.checkCancellation()

                return .urlSession(
                    try await _createNewURLSessionClient(
                        id: sessionProviderID,
                        provider: provider,
                        sessionConfiguration: sessionConfiguration
                    )
                )
            }

            return try await lock.withLock {
                try Task.checkCancellation()

                if let item = tableLock.withLock({
                    _reusableItem(id: sessionProviderID, sessionConfiguration: sessionConfiguration)
                }),
                    case .urlSession = item
                {
                    return item
                }

                return .urlSession(
                    try await _createNewURLSessionClient(
                        id: sessionProviderID,
                        provider: provider,
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
        package typealias MonotonicInstant = UInt64

        static func monotonicNow() -> UInt64 {
            DispatchTime.now().uptimeNanoseconds
        }

        func isExpired(_ item: Item, at now: UInt64) -> Bool {
            // `now` is the instant the sweep was asked to run at (a default argument, evaluated
            // before it takes ``tableLock``), and a client resolved in the meantime, or one a
            // test stamps after choosing the instant, is stamped later than that. An unsigned
            // `now - readAt` then underflows, which traps. An item newer than the instant being
            // judged is, by definition, not old enough to expire.
            guard now > item.readAt else {
                return false
            }

            return now - item.readAt > lifetime
        }
        #else
        package typealias MonotonicInstant = ContinuousClock.Instant

        static func monotonicNow() -> ContinuousClock.Instant {
            ContinuousClock.now
        }

        func isExpired(_ item: Item, at now: ContinuousClock.Instant) -> Bool {
            item.readAt.duration(to: now) > .nanoseconds(lifetime)
        }
        #endif

        /// Un-pools every client that has been idle for longer than `lifetime`.
        ///
        /// Only un-pools, for both backends: a client retires itself once the last reference to it
        /// goes (`Internals.Client.deinit`, `Internals.URLSessionClient.deinit`), including one a
        /// caller was handed just before this sweep ran and has not started using yet. `isRunning`
        /// flips as soon as `execute()` registers an operation, which both executors do *before*
        /// they wait on `throttledExecutor.acquire()`, so a client with callers queued behind its
        /// limit reads as busy here. One that has been handed out but not asked anything yet still
        /// reads as idle. Shutting it down explicitly from here
        /// would close it out from under that caller instead of merely un-pooling it, which is the
        /// same hazard `_evictIfNeeded(protecting:)`'s doc comment describes for the ceiling path.
        ///
        /// Does not take ``lock``, only ``tableLock``. The whole sweep is one synchronous pass over
        /// the table, atomic under ``tableLock`` like every other read and write of it, so it has
        /// nothing to serialize against that ``lock`` would add: a resolution stamps `readAt` and
        /// appends or evicts under ``tableLock`` too, and what ``lock`` orders (one resolution
        /// checking the table, building a client and adding it before the next looks) is not
        /// something a sweep takes part in. Queued behind it, a sweep (which runs at `.utility`)
        /// would sit in the line every client resolution waits in, and `AsyncLock` does not raise
        /// the priority of the task ahead of a waiting one: an interactive request would wait for
        /// the scheduling of a low priority task that has nothing to do with it.
        ///
        /// Also forgets the session limits nothing uses any more (``removeDeadThrottles()``), which
        /// is after the clients above have gone: the last client of a session going away is what
        /// ends its limit. Those are not counted by ``maximumCount`` and need no ceiling of
        /// their own: each is alive only while a client, a waiter or a slot holder holds it, so
        /// there are never more than the clients (bounded by ``maximumCount`` when pooled, by the
        /// requests in flight when not) can account for, and a dead one is dropped the next time
        /// a limit is added or a sweep runs.
        ///
        /// - Parameter now: Defaults to the monotonic clock. Not `private` and not fixed to it, so a
        /// test can run one sweep at an instant of its choosing, and so decide what is "idle for
        /// longer than `lifetime`" without waiting that long for it.
        package func cleanupIfNeeded(at now: MonotonicInstant = ClientManager.monotonicNow()) async {
            unpoolExpiredClients(at: now)

            // After the clients above have gone, which is the only thing that can end a session's
            // limit: it has to be a separate call, so that the clients are not still alive in this
            // frame when the limits are looked at.
            removeDeadThrottles()
        }

        private func unpoolExpiredClients(at now: MonotonicInstant) {
            // Dropped off `tableLock`, below: a client that nobody else holds retires itself
            // when its last reference goes, which can mean tearing down its connections and
            // identity, and that does not belong under a mutex every lookup also takes.
            let expired = tableLock.withLock { () -> [Item] in
                var expired = [Item]()

                for (key, items) in _table {
                    var surviving = [Item]()

                    for item in items {
                        if item.client.isRunning {
                            surviving.append(item.updatingReadAt())
                            continue
                        }

                        // An operation completed since this item was last touched (e.g. between
                        // two sequential calls on the same resolved client, such as cache
                        // revalidation's `HEAD` followed by the real `GET`), so this client was
                        // active more recently than `readAt` alone suggests, even though
                        // `isRunning` just read `false` above. Refreshing `readAt` here stops a
                        // caller mid-way through such a sequence from having its client un-pooled
                        // in the gap between the two calls, and so from losing the reuse it
                        // expects. See `Internals.ClientOperationQueue.generation`'s own doc
                        // comment.
                        if item.client.operationGeneration != item.lastKnownOperationGeneration {
                            surviving.append(item.updatingReadAt())
                            continue
                        }

                        if isExpired(item, at: now) {
                            expired.append(item)
                        } else {
                            surviving.append(item)
                        }
                    }

                    _table[key] = surviving.isEmpty ? nil : surviving
                }

                return expired
            }

            withExtendedLifetime(expired) {}
        }

        // MARK: - Throttles

        /// The throttle every client of one session admits its requests through, which is what
        /// makes `maximumConcurrentConnections` a limit of the session and not of whichever client
        /// a request happened to get.
        ///
        /// A session is its provider (`SessionProvider.uniqueIdentifier(with:)`, whatever executor
        /// resolves: the limit counts requests, not transports) and the limit it declares. Every
        /// request of the session, with a poolable configuration or not, gets a handle on the same
        /// semaphore for as long as that semaphore is in use, so 50 requests with a redirect
        /// strategy, each with a client of its own, still queue behind the same two slots. It is
        /// also what keeps the limit whole across a client the pool has let go of while callers
        /// still hold it and the one that replaces it.
        ///
        /// Two requests of one provider that declare *different* limits are two sessions as far as
        /// this goes: each limit is a cap on the requests that declare it, and they do not count
        /// against each other. The alternatives all go wrong in one way or another. The first
        /// limit to arrive winning would throttle a session to a number it never asked for, for as
        /// long as the winner lives, and which one that is depends on who asked first. The
        /// smallest winning would need a semaphore that can shrink while requests hold its slots
        /// (`AsyncCancellableSemaphore`'s count is fixed), and growing one back when the small one
        /// leaves would be as bad. Keying on the limit needs neither, cannot make one session wait
        /// for another's slots, and is what the clients did before: the limit is part of a
        /// configuration's identity (`Internals.Session.Configuration.==`), so two limits never
        /// shared a client either.
        ///
        /// A limit of zero or less, or none, is no limit at all (see
        /// `Internals.ThrottledExecutor.init(maximumConcurrentConnections:)`) and never touches
        /// the table.
        package func throttledExecutor(
            provider: SessionProvider,
            maximumConcurrentConnections: Int?
        ) -> Internals.ThrottledExecutor {
            guard let maximumConcurrentConnections, maximumConcurrentConnections > .zero else {
                return Internals.ThrottledExecutor(maximumConcurrentConnections: nil)
            }

            let key = ThrottleKey(
                providerID: provider.uniqueIdentifier(
                    with: SessionProviderOptions(isCompatibleWithNetworkFramework: false)
                ),
                maximumConcurrentConnections: maximumConcurrentConnections
            )

            return tableLock.withLock {
                if let semaphore = _throttles[key]?.semaphore {
                    return Internals.ThrottledExecutor(sharing: semaphore)
                }

                // A new session's limit is the moment the table grows, and so the moment the dead
                // ones are dropped: it never holds more than the live limits and the ones that
                // died since the last time a limit was added or a sweep ran, however many
                // different sessions come and go.
                _removeDeadThrottles()

                let semaphore = AsyncCancellableSemaphore(permits: maximumConcurrentConnections)
                _throttles[key] = WeakSemaphore(semaphore)

                return Internals.ThrottledExecutor(sharing: semaphore)
            }
        }

        /// Forgets the limits nothing uses any more. Part of the sweep (``cleanupIfNeeded(at:)``).
        func removeDeadThrottles() {
            tableLock.withLock { _removeDeadThrottles() }
        }

        /// - Warning: Lockless. The caller must be holding ``tableLock``.
        func _removeDeadThrottles() {
            _throttles = _throttles.filter { $0.value.semaphore != nil }
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
        /// single insert that follows. Same shape as `Internals.Storage._evictIfNeeded()`.
        ///
        /// The ceiling never gates service. Only clients with nothing in flight are candidates,
        /// and a caller is never made to wait for one to free up or turned away because there is
        /// nothing to evict: a table whose every entry is mid-request simply overshoots, and the
        /// `lifetime` sweep and the next insert with something idle in it bring it back down.
        /// Delaying a request, or tearing connections down out from under live ones, would trade a
        /// caller's latency for a bookkeeping limit, which is the wrong way round.
        ///
        /// Evicting is only ever *un-caching*, never shutting down, for both backends. A client
        /// retires itself once the last reference goes (`Internals.Client.deinit`,
        /// `Internals.URLSessionClient.deinit`), so a caller that was handed one and has not
        /// started its request yet (where `isRunning` is still `false`) keeps it alive by holding
        /// it. Shutting it down here would race that gap: `HTTPClientError.alreadyShutdown` for
        /// `.nio`, a task created on an invalidated session for `.urlSession`.
        ///
        /// - Parameter protecting: The client the caller is in the middle of handing out. It is
        /// idle by definition (nothing has been asked of it yet) and its entry is the newest in
        /// the table, so without this it is the *first* thing an at-capacity insert evicts, and
        /// the table is what lets the next caller with the same configuration find it.
        ///
        /// - Returns: The clients that were un-pooled, so the caller can let go of them *after*
        ///   releasing ``tableLock``: one that nobody else holds retires itself the moment its last
        ///   reference goes, and that can mean tearing down its connections and client identity.
        @discardableResult
        func _evictIfNeeded(
            protecting protectedClient: Internals.ClientManager.Client? = nil
        ) -> [Internals.ClientManager.Client] {
            let count = _table.values.reduce(0) { $0 + $1.count }

            guard count > maximumCount else {
                return []
            }

            let target = max(maximumCount - (maximumCount / 4), 1)
            let protectedIdentifier = protectedClient?.objectIdentifier

            let evictable =
                _table
                .flatMap { key, items in
                    items.enumerated().map { (key: key, offset: $0.offset, item: $0.element) }
                }
                .filter {
                    !$0.item.client.isRunning && $0.item.client.objectIdentifier != protectedIdentifier
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

            return evictable.map(\.item.client)
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
        /// NIOSSL-backed alike) and, for mTLS, builds the client identity
        /// (`Internals.RawBytesIdentityBuilder`), none of which is `async`. Calling it inline here would block whichever
        /// Swift Concurrency cooperative thread reached this cache miss for as long as that takes;
        /// `FileSystemManager.run` is the same escape hatch every other blocking file operation in
        /// `Internals` already uses for exactly that reason (see its own doc comment).
        private func _createNewURLSessionClient(
            id: String,
            provider: SessionProvider,
            sessionConfiguration: Internals.Session.Configuration
        ) async throws -> Internals.URLSessionClient {
            let throttledExecutor = self.throttledExecutor(
                provider: provider,
                maximumConcurrentConnections: sessionConfiguration.maximumConcurrentConnections
            )

            let client = try await Internals.FileSystemManager.run {
                try Internals.URLSessionClient(
                    configuration: sessionConfiguration.buildURLSessionConfiguration(),
                    secureConnection: sessionConfiguration.secureConnection,
                    redirectConfiguration: sessionConfiguration.redirectConfiguration
                        ?? .default,
                    urlOverrides: sessionConfiguration.urlOverrides,
                    proxy: sessionConfiguration.proxy,
                    throttledExecutor: throttledExecutor,
                    acceptEncoding: Internals.URLSessionClient.announcedAcceptEncoding(
                        for: sessionConfiguration.decompression
                    )
                )
            }

            // A configuration that can never be pooled (`isPoolable == false`) is not tracked,
            // same as the `.nio` side: nothing could ever be handed this entry again, so it would
            // only sit in the table, with its whole `URLSession`, until the sweep or the
            // `maximumCount` ceiling got to it. The caller owns that client instead, and
            // `Internals.URLSessionClient` is what keeps it alive for as long as a request is
            // using it and invalidates its session in `deinit` once nothing is, whether the
            // request completed, failed or was cancelled, or never got as far as being sent.
            guard sessionConfiguration.isPoolable else {
                return client
            }

            // Pooled clients are also owned by the table, which is what keeps one alive between
            // requests.
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

            withExtendedLifetime(evicted) {}

            return client
        }
        #endif
    }
}
