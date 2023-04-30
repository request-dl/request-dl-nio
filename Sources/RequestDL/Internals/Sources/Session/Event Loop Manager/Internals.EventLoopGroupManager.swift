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

        func provider(
            _ sessionProvider: SessionProvider
        ) -> EventLoopGroup {
            let group = groups[sessionProvider.id] ?? sessionProvider.group()
            groups[sessionProvider.id] = group
            return group
        }
    }
}
