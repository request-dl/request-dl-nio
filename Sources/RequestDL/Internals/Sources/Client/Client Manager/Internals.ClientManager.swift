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
            try await lock.withLock {
                if var items = _table[provider.id] {
                    if let (index, item) = items.enumerated().first(where: { $1.configuration == configuration }) {
                        items[index] = item.updatingReadAt()
                        _table[provider.id] = items
                        return item.client
                    }
                }

                let eventLoopGroup = await EventLoopGroupManager.shared.provider(provider)

                return try _createNewClient(
                    id: provider.id,
                    eventLoopGroup: eventLoopGroup,
                    configuration: configuration
                )
            }
        }

        // MARK: - Private methods

        fileprivate func scheduleCleanup() {
            _Concurrency.Task(priority: .background) {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime))
                await cleanupIfNeeded()
                scheduleCleanup()
            }
        }

        private func cleanupIfNeeded() async {
            await lock.withLock {
                let now = Date()
                let lifetime = Double(lifetime) / 1_000_000_000

                for (key, items) in _table {
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
                    _table[key] = items.isEmpty ? nil : items
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
