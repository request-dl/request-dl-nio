/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix

extension Internals {

    struct Session: Sendable {

        // MARK: - Internal properties

        let provider: SessionProvider
        let configuration: Internals.Session.Configuration
        let manager: Internals.ClientManager

        // MARK: - Inits

        init(
            provider: SessionProvider,
            configuration: Configuration
        ) {
            self.provider = provider
            self.configuration = configuration
            self.manager = .shared
        }

        // MARK: - Internal methods

        func request(_ request: Request) async throws -> SessionTask {
            let client = try await manager.client(
                provider: provider,
                configuration: configuration
            )

            let upload = AsyncStream<Int>()
            let head = AsyncStream<ResponseHead>()
            let download = DownloadBuffer(readingMode: request.readingMode)

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

            let eventLoopFuture = client.execute(
                request: request,
                delegate: delegate
            )

            let sessionTask = SessionTask(response)
            sessionTask.attach(eventLoopFuture)
            return sessionTask
        }
    }
}
