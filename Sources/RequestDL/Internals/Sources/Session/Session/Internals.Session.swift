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
        let configuration: Internals.Session.Configuration
        let manager: Internals.ClientManager
        let logger: Logger

        // MARK: - Inits

        init(
            provider: SessionProvider,
            configuration: Configuration,
            logger: Logger = .disabled
        ) {
            self.provider = provider
            self.configuration = configuration
            self.manager = .shared
            self.logger = logger
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
                uploadingBytes: request.body?.totalSize ?? .zero,
                upload: upload,
                head: head,
                download: download.stream
            )

            let request = try request.build()

            let unsafeTask = client.execute(
                request: request,
                delegate: delegate,
                logger: logger
            )

            return SessionTask(
                response: response,
                seed: unsafeTask()
            )
        }
    }
}
