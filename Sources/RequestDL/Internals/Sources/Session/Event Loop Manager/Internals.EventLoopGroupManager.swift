/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

extension Internals {

    class EventLoopGroupManager {

        static let shared = EventLoopGroupManager()

        private let queue: OperationQueue
        private var groups: [String: EventLoopGroup] = [:]

        init() {
            queue = OperationQueue()
            queue.qualityOfService = .background
        }

        func client(
            _ configuration: HTTPClient.Configuration,
            for sessionProvider: SessionProvider
        ) async -> HTTPClient {
            await withCheckedContinuation { continuation in
                queue.addOperation {
                    let group = self.groups[sessionProvider.id] ?? sessionProvider.group()
                    self.groups[sessionProvider.id] = group
                    continuation.resume(returning: HTTPClient(
                        eventLoopGroupProvider: .shared(group),
                        configuration: configuration
                    ))
                }
            }
        }
    }
}
