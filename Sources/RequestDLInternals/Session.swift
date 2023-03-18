//
//  File.swift
//  
//
//  Created by Brenno on 17/03/23.
//

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix

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

    static let shared = MultiThreadedEventLoopGroup(numberOfThreads: ProcessInfo().processorCount)
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

    func request(_ request: Request) throws -> ResponseStream {
        let queue = OperationQueue()

        let upload = Stream<Int>(queue: queue)
        let head = Stream<ResponseHead>(queue: queue)
        let download = Stream<UInt8>(queue: queue)

        let delegate = StreamResponse(
            upload: upload,
            head: head,
            download: download
        )

        let request = try request.build()

        let futurePromise = client.execute(
            request: request,
            delegate: delegate
        ).futureResult

        futurePromise.whenComplete { _ in
            Task {
                try await client.shutdown()
            }
        }
        
        return reduce(
            queue: queue,
            upload: upload,
            head: head,
            download: download
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
