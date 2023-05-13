/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient
import Semaphore

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
            _ sessionProvider: SessionProvider
        ) async -> EventLoopGroup {
            if case .background = _Concurrency.Task.currentPriority {
                return await _provider(sessionProvider)
            } else {
                return await _Concurrency.Task.detached(priority: .background) {
                    await self._provider(sessionProvider)
                }.value
            }
        }

        // MARK: - Unsafe methods

        private func _provider(
            _ sessionProvider: SessionProvider
        ) async -> EventLoopGroup {
            await lock.withLock {
                let group = _groups[sessionProvider.id] ?? sessionProvider.group()
                _groups[sessionProvider.id] = group
                return group
            }
        }
    }
}
