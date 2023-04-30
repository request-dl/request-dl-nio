/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient
import _Concurrency

extension Internals {

    @RequestActor
    class EventLoopGroupManager {

        static let shared = EventLoopGroupManager()

        private var groups: [String: EventLoopGroup] = [:]

        private func _provider(
            _ sessionProvider: SessionProvider
        ) async -> EventLoopGroup {
            let group = groups[sessionProvider.id] ?? sessionProvider.group()
            groups[sessionProvider.id] = group
            return group
        }

        // SwiftNIO requires that event loop group be instantiated
        // in background thread.
        //
        // Don't remove this method
        func provider(
            _ sessionProvider: SessionProvider
        ) async -> EventLoopGroup {
            await _Concurrency.Task(priority: .background) {
                await _provider(sessionProvider)
            }.value
        }
    }
}
