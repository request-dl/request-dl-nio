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

        Task {
            try? await promise.get()
            try? await client.shutdown()
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

public struct Session {

    private let client: () async -> HTTPClient
    public let configuration: Configuration

    public init(
        provider: Provider,
        configuration: Configuration
    ) async {
        self.configuration = configuration

        client = {
            await EventLoopGroupManager.shared.client(
                id: provider.id,
                factory: { provider.build() },
                configuration: configuration.build()
            )
        }
    }

    public func request(_ request: Request) async throws -> SessionTask {
        let upload = DataStream<Int>()
        let head = DataStream<ResponseHead>()
        let download = DownloadBuffer(readingMode: configuration.readingMode)

        let delegate = ClientResponseReceiver(
            upload: upload,
            head: head,
            download: download
        )

        let response = AsyncResponse(
            upload: upload,
            head: head,
            download: download.stream
        )

        let request = try request.build()
        let client = await client()

        let eventLoopFuture = client.execute(
            request: request,
            delegate: delegate
        ).futureResult

        let sessionTask = SessionTask(response)
        sessionTask.attach(client, eventLoopFuture)
        return sessionTask
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
