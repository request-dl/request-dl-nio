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

        func execute(
            requestConfiguration: RequestConfiguration,
            dataCache: DataCache,
            logger: Internals.TaskLogger?
        ) async throws -> SessionTask {
            let client = try await manager.client(
                provider: provider,
                sessionConfiguration: configuration
            )

            let cacheControl = CacheControl(
                requestConfiguration: requestConfiguration,
                dataCache: dataCache,
                logger: logger
            )

            switch await cacheControl(client) {
            case .task(let sessionTask):
                return sessionTask
            case .cache(let cache):
                return try await execute(
                    client: client,
                    requestConfiguration: requestConfiguration,
                    cache: cache,
                    logger: logger
                )
            }
        }

        // MARK: - Private methods

        private func execute(
            client: Internals.Client,
            requestConfiguration: RequestConfiguration,
            cache: ((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?
        ) async throws -> SessionTask {
            let upload = Internals.AsyncStream<Int>()
            let head = Internals.AsyncStream<Internals.ResponseHead>()
            let download = Internals.DownloadBuffer(readingMode: requestConfiguration.readingMode)

            let delegate = Internals.ClientResponseReceiver(
                url: requestConfiguration.url,
                upload: upload,
                head: head,
                download: download,
                cache: cache,
                logger: logger
            )

            let response = Internals.AsyncResponse(
                logger: logger,
                uploadingBytes: requestConfiguration.body?.totalSize ?? .zero,
                upload: upload,
                head: head,
                download: download.stream
            )

            let request = try requestConfiguration.build()

            let unsafeTask = client.execute(
                request: request,
                delegate: delegate,
                logger: logger
            )

            return SessionTask(
                seed: unsafeTask(),
                response: response
            )
        }
    }
}
