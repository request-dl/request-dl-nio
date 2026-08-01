//
// See LICENSE for this package's licensing information.
//

import NIOCore
import SwiftAsyncStream

#if canImport(Darwin)
import var Foundation.NSEC_PER_SEC
#endif

#if canImport(FoundationEssentials)
import struct FoundationEssentials.Date
#else
import struct Foundation.Date
#endif

extension Internals {

    final class ClientManager: @unchecked Sendable {

        // MARK: - Internal static properties

        static let lifetime: UInt64 = 5 * 60 * NSEC_PER_SEC
        static let shared = ClientManager(lifetime: lifetime)

        // MARK: - Private properties

        private let lock = AsyncLock()
        private let lifetime: UInt64

        private let tableLock = Lock()

        // MARK: - Unsafe properties

        private var _table = [String: [Item]]()

        // MARK: - Inits

        init(lifetime: UInt64) {
            self.lifetime = lifetime
            scheduleCleanup()
        }

        // MARK: - Internals methods

        func client(
            provider: SessionProvider,
            sessionConfiguration: Internals.Session.Configuration
        ) async throws -> Internals.Client {
            let options = SessionProviderOptions(
                isCompatibleWithNetworkFramework: sessionConfiguration.isCompatibleWithNetworkFramework
            )

            let sessionProviderID = provider.uniqueIdentifier(with: options)

            return try await lock.withLock {
                // `withLock` rather than a manual lock and unlock pair with a return in the
                // middle of it, which balances today and stops balancing on the next edit.
                if let client = tableLock.withLock({ _reusableClient(id: sessionProviderID, sessionConfiguration: sessionConfiguration) }) {
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

                    await cleanupIfNeeded()
                }
            }
        }

        private func cleanupIfNeeded() async {
            await lock.withLock {
                // Monotonic, not wall clock. `Date` moves when the user or NTP moves the system
                // clock: backwards and no client is ever recycled, forwards and every client is
                // eligible at once, including one handed out a moment ago and about to be used.
                let now = DispatchTime.now().uptimeNanoseconds

                for (key, items) in tableLock.withLock({ _table }) {
                    var surviving = [Item]()

                    for item in items {
                        if item.client.isRunning {
                            surviving.append(item.updatingReadAt())
                            continue
                        }

                        guard now - item.readAt > lifetime else {
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
            guard
                var items = _table[id],
                let index = items.firstIndex(where: { $0.sessionConfiguration == sessionConfiguration })
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
                configuration: try sessionConfiguration.build()
            )

            tableLock.withLock {
                var items = _table[id] ?? []

                items.append(.createNew(
                    sessionConfiguration: sessionConfiguration,
                    client: client
                ))

                _table[id] = items
            }

            return client
        }
    }
}
