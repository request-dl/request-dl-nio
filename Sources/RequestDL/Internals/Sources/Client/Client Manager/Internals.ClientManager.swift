/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    @HTTPClientActor
    class ClientManager {

        static let lifetime: Int = 5_000_000_000 * 60
        static let shared = ClientManager(lifetime: lifetime)

        private let lifetime: Int
        private var table = [String: [Item]]()

        private var pendingOperations = [String: _Concurrency.Task<Void, Never>]()

        init(lifetime: Int) {
            self.lifetime = lifetime
            scheduleCleanup()
        }

        func client(
            provider: SessionProvider,
            configuration: Internals.Session.Configuration
        ) async throws -> Internals.Client {
            await waitForPendingOperation(provider)

            if var items = table[provider.id] {
                if let (index, item) = items.enumerated().first(where: { $1.configuration == configuration }) {
                    items[index] = item.updatingReadAt()
                    table[provider.id] = items
                    return item.client
                }
            }

            return try await addOperation(provider.id) {
                let eventLoopGroup = await EventLoopGroupManager.shared.provider(provider)

                return try self.createNewClient(
                    id: provider.id,
                    eventLoopGroup: eventLoopGroup,
                    configuration: configuration
                )
            }
        }

        private func createNewClient(
            id: String,
            eventLoopGroup: EventLoopGroup,
            configuration: Internals.Session.Configuration
        ) throws -> Internals.Client {
            let client = Internals.Client(
                eventLoopGroupProvider: .shared(eventLoopGroup),
                configuration: try configuration.build()
            )

            var items = table[id] ?? []

            items.append(.createNew(
                configuration: configuration,
                client: client
            ))

            table[id] = items
            return client
        }
    }
}

extension Internals.ClientManager {

    fileprivate func scheduleCleanup() {
        _Concurrency.Task(priority: .background) {
            try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime))
            await cleanupIfNeeded()
            scheduleCleanup()
        }
    }

    private func cleanupIfNeeded() async {
        let now = Date()
        let lifetime = Double(lifetime) / 1_000_000_000

        for (key, items) in table {
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
            table[key] = items.isEmpty ? nil : items
        }
    }
}

extension Internals.ClientManager {

    fileprivate func waitForPendingOperation(_ provider: SessionProvider) async {
        if let operation = pendingOperations[provider.id] {
            await operation.value
        }
    }

    fileprivate func addOperation<Value>(
        _ id: String,
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        let task = _Concurrency.Task(priority: _Concurrency.Task.currentPriority) {
            try await operation()
        }

        let _operation = _Concurrency.Task(priority: _Concurrency.Task.currentPriority) {
            do {
                _ = try await task.value
            } catch {}
        }

        pendingOperations[id] = _operation
        let value = try await task.value
        pendingOperations[id] = nil
        return value
    }
}
