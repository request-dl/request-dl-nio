/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix

class SessionTask {

    let response: Internals.AsyncResponse
    private var payload: (HTTPClient, EventLoopFuture<Void>)?
    private var complete: Bool = false

    init(_ response: Internals.AsyncResponse) {
        self.response = response
    }

    func attach(_ client: HTTPClient, _ eventLoopFuture: EventLoopFuture<Void>) {
        payload = (client, eventLoopFuture.always { [weak self] _ in
            self?.complete = true
        })
    }

    func shutdown() {
        guard let (client, promise) = payload else {
            return
        }

        self.payload = nil

        _Concurrency.Task {
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

extension Internals {

    struct Session {

        private let client: (Internals.Session.Configuration) async throws -> HTTPClient
        var configuration: Internals.Session.Configuration

        init(
            provider: SessionProvider,
            configuration: Configuration
        ) async throws {
            self.configuration = configuration

            client = { configuration in
                await EventLoopGroupManager.shared.client(
                    try configuration.build(),
                    for: provider
                )
            }
        }

        func request(_ request: Request) async throws -> SessionTask {
            let upload = DataStream<Int>()
            let head = DataStream<ResponseHead>()
            let download = DownloadBuffer(readingMode: configuration.readingMode)

            let delegate = ClientResponseReceiver(
                url: request.url,
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
            let client = try await client(configuration)

            let eventLoopFuture = client.execute(
                request: request,
                delegate: delegate
            ).futureResult

            let sessionTask = SessionTask(response)
            sessionTask.attach(client, eventLoopFuture)
            return sessionTask
        }
    }
}
