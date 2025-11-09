/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    class ClientManager: @unchecked Sendable {

        // MARK: - Internal static properties

        static let lifetime: UInt64 = 5_000_000_000 * 60
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
            configuration: Internals.Session.Configuration
        ) async throws -> Internals.Client {
            let options = SessionProviderOptions(
                isCompatibleWithNetworkFramework: configuration.isCompatibleWithNetworkFramework
            )

            let sessionProviderID = provider.uniqueIdentifier(with: options)

            return try await lock.withLock {
                tableLock.lock()
                if var items = _table[sessionProviderID] {
                    if let (index, item) = items.enumerated().first(where: { $1.configuration == configuration }) {
                        items[index] = item.updatingReadAt()
                        _table[sessionProviderID] = items
                        tableLock.unlock()
                        return item.client
                    }
                }
                tableLock.unlock()

                let eventLoopGroup = await EventLoopGroupManager.shared.provider(
                    provider,
                    with: options
                )

                return try _createNewClient(
                    id: sessionProviderID,
                    eventLoopGroup: eventLoopGroup,
                    configuration: configuration
                )
            }
        }

        // MARK: - Private methods

        fileprivate func scheduleCleanup() {
            _Concurrency.Task.detached(priority: .background) { [weak self, lifetime] in
                while true {
                    try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime))

                    guard let self else {
                        return
                    }

                    await cleanupIfNeeded()
                }
            }
        }

        private func cleanupIfNeeded() async {
            await lock.withLock {
                let now = Date()
                let lifetime = Double(lifetime) / 1_000_000_000

                for (key, items) in tableLock.withLock({ _table }) {
                    var optionalItems = items as [Internals.ClientManager.Item?]

                    for (index, item) in items.enumerated() {
                        if item.client.isRunning {
                            optionalItems[index] = item.updatingReadAt()
                        } else if item.readAt.distance(to: now) > lifetime {
                            if (try? await item.client.shutdown()) ?? false {
                                optionalItems[index] = nil
                            }
                        }
                    }

                    let items = optionalItems.compactMap { $0 }
                    tableLock.withLock {
                        _table[key] = items.isEmpty ? nil : items
                    }
                }
            }
        }

        // MARK: - Unsafe methods

        private func _createNewClient(
            id: String,
            eventLoopGroup: EventLoopGroup,
            configuration: Internals.Session.Configuration
        ) throws -> Internals.Client {
            let client = Internals.Client(
                eventLoopGroupProvider: .shared(eventLoopGroup),
                configuration: try configuration.build()
            )

            tableLock.lock()
            defer { tableLock.unlock() }

            var items = _table[id] ?? []

            items.append(.createNew(
                configuration: configuration,
                client: client
            ))

            _table[id] = items
            return client
        }
    }
}
