/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix

public class SessionTask {

    public let response: AsyncResponse
    private let client: HTTPClient
    private let promise: EventLoopFuture<Void>

    public init(
        response: AsyncResponse,
        client: HTTPClient,
        promise: EventLoopFuture<Void>
    ) {
        self.response = response
        self.client = client
        self.promise = promise
    }

    public func shutdown() {
        promise.flatMap { [client] in
            client.shutdown()
        }.whenComplete {
            print("[Shutdown]", $0)
        }
    }

    deinit {
        shutdown()
    }
}

actor EventLoopManager {

    public static let shared = EventLoopManager()

    private var groups: [String: EventLoopGroup] = [:]

    func newClient(
        id: String,
        factory: @escaping () -> EventLoopGroup,
        configuration: HTTPClient.Configuration
    ) -> HTTPClient {
        if let group = groups[id] {
            print("Using registered")
            return HTTPClient(
                eventLoopGroupProvider: .shared(group),
                configuration: configuration
            )
        } else {
            print("Creating new")
            let group = factory()
            groups[id] = group
            return HTTPClient(
                eventLoopGroupProvider: .shared(group),
                configuration: configuration
            )
        }
    }
}

public typealias EventLoopGroup = NIOCore.EventLoopGroup

extension MultiThreadedEventLoopGroup {

    static let shared = MultiThreadedEventLoopGroup(numberOfThreads: ProcessInfo.processInfo.processorCount)
}

public struct Session {

    private let client: HTTPClient

    public init(
        provider: Provider,
        configuration: Configuration
    ) async {
        client = await EventLoopManager.shared.newClient(
            id: provider.id,
            factory: { provider.build() },
            configuration: configuration.build()
        )
    }

    func regular(_ url: String) async throws -> HTTPClient.Response {
        let response = try await client.execute(request: .init(url: url)).get()
        try await client.shutdown()
        return response
    }

    func request(_ request: Request) throws -> SessionTask {
        let upload = DataStream<Int>()
        let head = DataStream<ResponseHead>()
        let download = DataStream<ByteBuffer>()

        let delegate = ClientResponseReceiver(
            upload: upload,
            head: head,
            download: download
        )

        let response = AsyncResponse(
            upload: upload,
            head: head,
            download: download
        )

        let request = try request.build()

        let eventLoopFuture = client.execute(
            request: request,
            delegate: delegate
        )
        
        return .init(
            response: response,
            client: client,
            promise: eventLoopFuture.futureResult
        )
    }

    func invalidate() async throws {
        try await client.shutdown()
    }
}

extension Session {

    public enum Provider {
        case shared
        case identifier(String, numberOfThreads: Int = 1)
        case custom(EventLoopGroup)
    }
}

extension Session.Provider {

    var id: String {
        switch self {
        case .shared:
            return "\(ObjectIdentifier(MultiThreadedEventLoopGroup.shared))"
        case .identifier(let id, _):
            return id
        case .custom(let eventLoopGroup):
            return "\(ObjectIdentifier(eventLoopGroup))"
        }
    }

    func build() -> EventLoopGroup {
        switch self {
        case .shared:
            return MultiThreadedEventLoopGroup.shared
        case .identifier(_, let numberOfThreads):
            return MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
        case .custom(let eventLoopGroup):
            return eventLoopGroup
        }
    }
}
