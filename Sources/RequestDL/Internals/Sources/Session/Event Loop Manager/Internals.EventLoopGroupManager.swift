/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient
import _Concurrency

extension Internals {

    actor EventLoopGroupManager {

        static let shared = EventLoopGroupManager()

        private var groups: [String: EventLoopGroup] = [:]

        private func _makeClient(
            _ configuration: HTTPClient.Configuration,
            for sessionProvider: SessionProvider
        ) -> HTTPClient {
            let group = groups[sessionProvider.id] ?? sessionProvider.group()
            groups[sessionProvider.id] = group
            return .init(
                eventLoopGroupProvider: .shared(group),
                configuration: configuration
            )
        }

        nonisolated func client(
            _ configuration: HTTPClient.Configuration,
            for sessionProvider: SessionProvider
        ) async -> HTTPClient {
            await _Concurrency.Task(priority: .low) {
                await _makeClient(configuration, for: sessionProvider)
            }.value
        }
    }
}
