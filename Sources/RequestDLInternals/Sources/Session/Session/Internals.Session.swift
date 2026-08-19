//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Logging
import NIOCore
import NIOPosix

extension Internals {

    package struct Session: Sendable {

        // MARK: - Internal properties

        package let provider: SessionProvider
        package let configuration: Internals.Session.Configuration
        package let manager: Internals.ClientManager

        // MARK: - Inits

        package init(
            provider: SessionProvider,
            configuration: Configuration
        ) {
            self.provider = provider
            self.configuration = configuration
            self.manager = .shared
        }

        // MARK: - Internal methods

        package func client() async throws -> Internals.Client {
            try await manager.client(
                provider: provider,
                sessionConfiguration: configuration
            )
        }

        package func execute(
            client: Internals.Client,
            request: HTTPClient.Request,
            url: String,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            cache: ((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?
        ) async throws -> SessionTask {
            let upload = Internals.AsyncStream<Int>()
            let head = Internals.AsyncStream<Internals.ResponseHead>()
            let download = await Internals.DownloadBuffer(
                readingMode: readingMode
            )

            let delegate = Internals.ClientResponseReceiver(
                url: url,
                upload: upload,
                head: head,
                download: download,
                cache: cache,
                logger: logger
            )

            let response = Internals.AsyncResponse(
                logger: logger,
                uploadingBytes: uploadingBytes,
                upload: upload,
                head: head,
                download: download.stream
            )

            let unsafeTask = await client.execute(
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
