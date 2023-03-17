//
//  File.swift
//  
//
//  Created by Brenno on 17/03/23.
//

import Foundation
import AsyncHTTPClient
import NIOCore

public typealias EventLoopGroup = NIOCore.EventLoopGroup

public struct Session {

    private let client: HTTPClient

    public init(
        eventLoopGroupProvider: EventLoopGroupProvider,
        configuration: Configuration
    ) {
        client = .init(
            eventLoopGroupProvider: eventLoopGroupProvider,
            configuration: configuration.build()
        )
    }

    func request(_ request: Request) async throws -> AsyncResponse {
        let upload = await Stream<Int>()
        let head = await Stream<ResponseHead>()
        let download = await Stream<UInt8>()

        let delegate = StreamResponse(
            upload: upload,
            head: head,
            download: download
        )

        let request = try request.build()

        client.execute(
            request: request,
            delegate: delegate
        ).futureResult.whenCompleteBlocking(onto: .global(qos: .utility)) { _ in
            Task {
                try await client.shutdown()
            }
        }

        return .init(
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

    public typealias EventLoopGroupProvider = HTTPClient.EventLoopGroupProvider
}
