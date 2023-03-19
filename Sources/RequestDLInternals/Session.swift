/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix

public class SessionTask {

    public let response: AsyncResponse
    private var payload: (HTTPClient, EventLoopFuture<Void>)?
    private var complete: Bool = false

    public init(_ response: AsyncResponse) {
        self.response = response
    }

    func attach(_ client: HTTPClient, _ eventLoopFuture: EventLoopFuture<Void>) {
        payload = (client, eventLoopFuture.always { [weak self] _ in
            self?.complete = true
        })
    }

    public func shutdown() {
        guard let (client, promise) = payload else {
            return
        }

        self.payload = nil

        promise.whenComplete { _ in
            try? client.syncShutdown()
        }
    }

    deinit {
        if complete {
            try? payload?.0.syncShutdown()
        } else {
            shutdown()
        }
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

    public func request(_ request: Request) throws -> SessionTask {
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

        let request = try request.build(client.eventLoopGroup.next())

        let eventLoopFuture = client.execute(
            request: request,
            delegate: delegate
        )
        
        let sessionTask = SessionTask(response)
        sessionTask.attach(client, eventLoopFuture.futureResult)
        return sessionTask
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
        case .identifier(let id, let numberOfThreads):
            return "\(id).\(numberOfThreads)"
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
