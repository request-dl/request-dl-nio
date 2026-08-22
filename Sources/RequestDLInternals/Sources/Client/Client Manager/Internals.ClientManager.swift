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
            let options = SessionProviderOptions(
                isCompatibleWithNetworkFramework: sessionConfiguration.isCompatibleWithNetworkFramework
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
                if let client = tableLock.withLock({
                    _reusableClient(id: sessionProviderID, sessionConfiguration: sessionConfiguration)
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
        private func _reusableClient(
            id: String,
            sessionConfiguration: Internals.Session.Configuration
        ) -> Internals.Client? {
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
                        client: client
                    )
                )

                _table[id] = items
            }

            return client
        }
    }
}
