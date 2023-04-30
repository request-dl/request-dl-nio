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

        func client(
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
    }
}
