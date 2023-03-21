/*
 See LICENSE for this package's licensing information.
*/

import NIOCore
import AsyncHTTPClient

actor EventLoopGroupManager {

    public static let shared = EventLoopGroupManager()

    private var groups: [String: EventLoopGroup] = [:]

    func client(
        id: String,
        factory: @escaping () -> EventLoopGroup,
        configuration: HTTPClient.Configuration
    ) -> HTTPClient {
        if let group = groups[id] {
            return HTTPClient(
                eventLoopGroupProvider: .shared(group),
                configuration: configuration
            )
        } else {
            let group = factory()
            groups[id] = group
            return HTTPClient(
                eventLoopGroupProvider: .shared(group),
                configuration: configuration
            )
        }
    }
}
