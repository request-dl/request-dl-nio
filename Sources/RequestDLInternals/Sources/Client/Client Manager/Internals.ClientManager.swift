//
// See LICENSE for this package's licensing information.
//

import NIOCore
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

        package static let lifetime = TimeAmount.seconds(5 * 60)
        package static let shared = ClientManager(lifetime: lifetime)

        // MARK: - Private static properties

        /// Flags a `client(provider:sessionConfiguration:)` or `cleanupIfNeeded()` that is still
        /// running after 45s. Set higher than the other `AsyncLock`s in `Internals`:
        /// `cleanupIfNeeded()` shares this lock and can shut down several expired clients
        /// serially in one sweep, each a real network drain, so a wide margin is needed to avoid
        /// flagging a legitimately busy sweep. Development builds only — see
        /// `AsyncLock.Watchdog`.
        #if DEBUG
        private static let watchdog: AsyncLock.Watchdog? = .init(seconds: 45) {
            Internals.assertionFailure($0)
        }
        #else
        private static let watchdog: AsyncLock.Watchdog? = nil
        #endif

        // MARK: - Private properties

        private let lock = AsyncLock(watchdog: watchdog)
        private let lifetime: TimeAmount

        private let tableLock = Lock()

        // MARK: - Unsafe properties

        private var _table = [String: [Item]]()

        // MARK: - Inits

        package init(lifetime: TimeAmount) {
            self.lifetime = lifetime
            scheduleCleanup()
        }

        // MARK: - Internals methods

        package func client(
            provider: SessionProvider,
            sessionConfiguration: Internals.Session.Configuration
        ) async throws -> Internals.Client {
            try await _nioClient(
                provider: provider,
                sessionConfiguration: sessionConfiguration,
                isCompatibleWithNetworkFramework: sessionConfiguration.isCompatibleWithNetworkFramework
            )
        }

        /// Executor-aware counterpart to `client(provider:sessionConfiguration:)` -- resolves
        /// `sessionConfiguration.resolveExecutor()` and actually builds/caches the client that
        /// decision points to, rather than only deciding in the abstract. Covers both axes:
        /// `.urlSession` vs. not, and -- within the `.nio` branch -- plain NIO vs.
        /// NIOTransportServices, so `preferredExecutor(.nioTransportServices)`/
        /// `requiredExecutor(.nioTransportServices)` actually decide which event loop group a real
        /// request gets, not just `enableNetworkFramework`.
        ///
        /// Shares this manager's own `_table` with the NIO-only `client(provider:sessionConfiguration:)`
        /// above -- a `.urlSession` entry is keyed apart from a `.nio`/NIOTransportServices one for
        /// the same provider (see `_createNewURLSessionClient`'s `id`), so the two can never
        /// collide or be handed back for each other. Likewise, `_nioClient`'s own `isCompatibleWithNetworkFramework`
        /// parameter -- not `sessionConfiguration.isCompatibleWithNetworkFramework` -- is what
        /// keys a NIOTransportServices entry apart from a plain-NIO one here
        /// (`SessionProvider.uniqueIdentifier(with:)`'s `"NTW."` prefix reads that parameter, not
        /// `enableNetworkFramework` directly), so an executor-resolved and a flag-resolved client
        /// for the same provider can only ever collide if they'd have made the identical choice
        /// anyway.
        package func resolvedClient(
            provider: SessionProvider,
            sessionConfiguration: Internals.Session.Configuration
        ) async throws -> Internals.ClientManager.Client {
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

            let sessionProviderID =
                "URLSession."
                + provider.uniqueIdentifier(
                    with: SessionProviderOptions(isCompatibleWithNetworkFramework: false)
                )

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
                    try _createNewURLSessionClient(
                        id: sessionProviderID,
                        sessionConfiguration: sessionConfiguration
                    )
                )
            }
            #else
            return .nio(try await client(provider: provider, sessionConfiguration: sessionConfiguration))
            #endif
        }

        // MARK: - Private methods

        /// Shared body for `client(provider:sessionConfiguration:)` and `resolvedClient(provider:sessionConfiguration:)`'s
        /// `.nio`/`.nioTransportServices` branch -- the two differ only in *how* they decide
        /// `isCompatibleWithNetworkFramework` (the `enableNetworkFramework` flag directly, vs.
        /// `resolveExecutor()`'s own answer), never in what happens once that's decided.
        private func _nioClient(
            provider: SessionProvider,
            sessionConfiguration: Internals.Session.Configuration,
            isCompatibleWithNetworkFramework: Bool
        ) async throws -> Internals.Client {
            let options = SessionProviderOptions(
                isCompatibleWithNetworkFramework: isCompatibleWithNetworkFramework
            )

            let sessionProviderID = provider.uniqueIdentifier(with: options)

            return try await lock.withLock {
                // `AsyncLock` never aborts acquisition, so a task cancelled while queued behind
                // a cleanup sweep would otherwise still pay for (or trigger) client creation and
                // go on to fire a request nobody wants anymore. Checked first, before touching
                // the table, so a cancelled caller does no work at all here.
                try Task.checkCancellation()

                // `withLock` rather than a manual lock and unlock pair with a return in the
                // middle of it, which balances today and stops balancing on the next edit.
                if case .nio(let client) = tableLock.withLock({
                    _reusableItem(id: sessionProviderID, sessionConfiguration: sessionConfiguration)
                }) {
                    return client
                }

                let eventLoopGroup = await EventLoopGroupManager.shared.provider(
                    provider,
                    with: options
                )

                return try _createNewClient(
                    id: sessionProviderID,
                    eventLoopGroup: eventLoopGroup,
                    sessionConfiguration: sessionConfiguration
                )
            }
        }

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

                    await cleanupIfNeeded()
                }
            }
        }

        private func cleanupIfNeeded() async {
            await lock.withLock {
                // Monotonic, not wall clock. `Date` moves when the user or NTP moves the system
                // clock: backwards and no client is ever recycled, forwards and every client is
                // eligible at once, including one handed out a moment ago and about to be used.
                let now = {
                    #if canImport(Darwin)
                    DispatchTime.now().uptimeNanoseconds
                    #else
                    ContinuousClock.now
                    #endif
                }()

                for (key, items) in tableLock.withLock({ _table }) {
                    var surviving = [Item]()

                    for item in items {
                        if item.client.isRunning {
                            surviving.append(item.updatingReadAt())
                            continue
                        }

                        let isExpired: Bool = {
                            #if canImport(Darwin)
                            now - item.readAt > lifetime.nanoseconds
                            #else
                            item.readAt.duration(to: .now) > .nanoseconds(lifetime.nanoseconds)
                            #endif
                        }()

                        guard isExpired else {
                            surviving.append(item)
                            continue
                        }

                        if (try? await item.client.shutdown()) != true {
                            surviving.append(item)
                        }
                    }

                    tableLock.withLock {
                        _table[key] = surviving.isEmpty ? nil : surviving
                    }
                }
            }
        }

        // MARK: - Unsafe methods

        /// - Warning: Lockless. The caller must be holding ``tableLock``.
        ///
        /// Returns the cached `Internals.ClientManager.Client` regardless of which backend it
        /// wraps -- shared by both `client(provider:sessionConfiguration:)` (NIO-only, unwraps
        /// `.nio`) and `resolvedClient(provider:sessionConfiguration:)` (unwraps `.urlSession`),
        /// so the age/reuse logic below is written once rather than duplicated per backend.
        private func _reusableItem(
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
                            now - item.readAt <= lifetime.nanoseconds
                            #else
                            item.readAt.duration(to: .now) <= .nanoseconds(lifetime.nanoseconds)
                            #endif
                        }()
                })
            else { return nil }

            let item = items[index]

            items[index] = item.updatingReadAt()
            _table[id] = items

            return item.client
        }

        /// - Warning: Lockless with respect to ``tableLock``, which it takes itself.
        private func _createNewClient(
            id: String,
            eventLoopGroup: EventLoopGroup,
            sessionConfiguration: Internals.Session.Configuration
        ) throws -> Internals.Client {
            let client = Internals.Client(
                eventLoopGroupProvider: .shared(eventLoopGroup),
                configuration: try sessionConfiguration.build(),
                maximumConcurrentConnections: sessionConfiguration.maximumConcurrentConnections
            )

            tableLock.withLock {
                var items = _table[id] ?? []

                items.append(
                    .createNew(
                        sessionConfiguration: sessionConfiguration,
                        client: .nio(client)
                    )
                )

                _table[id] = items
            }

            return client
        }

        #if canImport(Darwin)
        /// - Warning: Lockless with respect to ``tableLock``, which it takes itself.
        ///
        /// `id` is expected to already carry `resolvedClient(provider:sessionConfiguration:)`'s
        /// `"URLSession."` prefix, keeping this entry apart from any `.nio` one the same provider
        /// might also have cached under its bare (or `"NTW."`-prefixed) id.
        private func _createNewURLSessionClient(
            id: String,
            sessionConfiguration: Internals.Session.Configuration
        ) throws -> Internals.URLSessionClient {
            let client = try Internals.URLSessionClient(
                configuration: sessionConfiguration.buildURLSessionConfiguration(),
                secureConnection: sessionConfiguration.secureConnection,
                redirectConfiguration: sessionConfiguration.redirectConfiguration
                    ?? .follow(max: 5, allowCycles: false),
                proxy: sessionConfiguration.proxy,
                maximumConcurrentConnections: sessionConfiguration.maximumConcurrentConnections
            )

            tableLock.withLock {
                var items = _table[id] ?? []

                items.append(
                    .createNew(
                        sessionConfiguration: sessionConfiguration,
                        client: .urlSession(client)
                    )
                )

                _table[id] = items
            }

            return client
        }
        #endif
    }
}
