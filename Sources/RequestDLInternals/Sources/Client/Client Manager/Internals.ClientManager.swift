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
        package static let shared = ClientManager(lifetime: lifetime)

        // MARK: - Private static properties

        /// Flags a `client(provider:sessionConfiguration:)` or `cleanupIfNeeded()` that is still
        /// running after 45s. Set higher than the other `AsyncLock`s in `Internals`:
        /// `cleanupIfNeeded()` shares this lock and can shut down several expired clients
        /// serially in one sweep, each a real network drain, so a wide margin is needed to avoid
        /// flagging a legitimately busy sweep. Development builds only. See
        /// `AsyncLock.Watchdog`.
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

        let tableLock = Lock()

        // MARK: - Unsafe properties

        var _table = [String: [Item]]()

        // MARK: - Inits

        package init(lifetime: Int64) {
            self.lifetime = lifetime
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
            // implementation): NIOCore being available here means `.nio` unconditionally, same
            // as this branch always returned before this function had a portable half to fall
            // through to below.
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
                            now - item.readAt > lifetime
                            #else
                            item.readAt.duration(to: .now) > .nanoseconds(lifetime)
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
        /// (`Internals.RawBytesIdentityBuilder`/`Internals.IdentityManager`) — none of which are
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
