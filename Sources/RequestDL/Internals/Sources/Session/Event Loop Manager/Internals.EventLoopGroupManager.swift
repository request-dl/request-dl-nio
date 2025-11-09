/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

extension Internals {

    final class EventLoopGroupManager: @unchecked Sendable {

        // MARK: - Internal static properties

        static let shared = EventLoopGroupManager()

        // MARK: - Private properties

        private let lock = AsyncLock()

        // MARK: - Unsafe properties

        @preconcurrency
        private var _groups: [String: EventLoopGroup] = [:]

        // MARK: - Internal methods

        func provider(
            _ sessionProvider: SessionProvider,
            with options: SessionProviderOptions
        ) async -> EventLoopGroup {
            if case .background = _Concurrency.Task.currentPriority {
                return await _provider(sessionProvider, with: options)
            } else {
                return await _Concurrency.Task.detached(priority: .background) {
                    await self._provider(sessionProvider, with: options)
                }.value
            }
        }

        // MARK: - Unsafe methods

        private func _provider(
            _ sessionProvider: SessionProvider,
            with options: SessionProviderOptions
        ) async -> EventLoopGroup {
            await lock.withLock {
                let sessionProviderID = sessionProvider.uniqueIdentifier(with: options)
                let group = _groups[sessionProviderID] ?? sessionProvider.group(with: options)
                _groups[sessionProviderID] = group
                return group
            }
        }
    }
}

struct Table<Key: Sendable, Value: Sendable>: Sendable {

    subscript(_ key: Key, default: Value) -> Value {
        get {
            self[key] ?? `default`
        }
        set {
            self[key] = newValue
        }
    }

    subscript(_ key: Key) -> Value? {
        get { fatalError() }
        set {}
    }
}
