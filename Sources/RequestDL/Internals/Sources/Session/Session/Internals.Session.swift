/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix
import Logging

extension Internals {

    struct Session: Sendable {

        // MARK: - Internal properties

        let provider: SessionProvider
        let logger: Logger?
        let configuration: Internals.Session.Configuration
        let manager: Internals.ClientManager

        // MARK: - Inits

        init(
            provider: SessionProvider,
            logger: Logger?,
            configuration: Configuration
        ) {
            self.provider = provider
            self.logger = logger
            self.configuration = configuration
            self.manager = .shared
        }

        // MARK: - Internal methods

        func execute(
            request: Request,
            dataCache: DataCache
        ) async throws -> SessionTask {
            let client = try await manager.client(
                provider: provider,
                configuration: configuration
            )

            let cacheControl = CacheControl(
                request: request,
                dataCache: dataCache,
                logger: logger
            )

            switch await cacheControl(client) {
            case .task(let sessionTask):
                return sessionTask
            case .cache(let cache):
                return try await execute(
                    client: client,
                    request: request,
                    cache: cache
                )
            }
        }

        // MARK: - Private methods

        private func execute(
            client: Internals.Client,
            request: Internals.Request,
            cache: ((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?
        ) async throws -> SessionTask {
            let upload = Internals.AsyncStream<Int>()
            let head = Internals.AsyncStream<Internals.ResponseHead>()
            let download = Internals.DownloadBuffer(readingMode: request.readingMode)

            let delegate = Internals.ClientResponseReceiver(
                url: request.url,
                upload: upload,
                head: head,
                download: download,
                cache: cache
            )

            let response = Internals.AsyncResponse(
                upload: upload,
                head: head,
                download: download.stream
            )

            let request = try request.build()

            let eventLoopFuture = client.execute(
                request: request,
                delegate: delegate,
                logger: logger ?? Internals.logginDisabled
            )

            let sessionTask = SessionTask(response)
            sessionTask.attach(eventLoopFuture)
            return sessionTask
        }
    }
}

extension Internals {

    static let logginDisabled = Logger(label: "request-dl.logging.disabled") { _ in
        SwiftLogNoOpLogHandler()
    }
}
