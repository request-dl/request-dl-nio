/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient
import _Concurrency

extension Internals {

    @HTTPClientActor
    class EventLoopGroupManager {

        static let shared = EventLoopGroupManager()

        private var groups: [String: EventLoopGroup] = [:]

        private func _provider(
            _ sessionProvider: SessionProvider
        ) -> EventLoopGroup {
            let group = self.groups[sessionProvider.id] ?? sessionProvider.group()
            self.groups[sessionProvider.id] = group
            return group
        }

        func provider(
            _ sessionProvider: SessionProvider
        ) async -> EventLoopGroup {
            if case .background = _Concurrency.Task.currentPriority {
                return _provider(sessionProvider)
            } else {
                return await _Concurrency.Task.detached(priority: .background) {
                    await self._provider(sessionProvider)
                }.value
            }
        }
    }
}
