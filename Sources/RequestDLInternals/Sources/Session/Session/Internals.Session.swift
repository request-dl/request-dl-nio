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

        /// Executor-aware counterpart to `client()` -- Phase 7b3 of `URLSESSION_TASK.md`. Returns
        /// whichever backend `configuration.resolveExecutor()` (Phase 3) actually points to,
        /// rather than always the NIO one `client()` above hands back unconditionally.
        ///
        /// Returns `Internals.ClientManager.Client` (the enum), not `any RequestExecutingClient`,
        /// because that protocol -- and both concrete conformances -- live in the `RequestDL`
        /// module, which depends on this one (`RequestDLInternals`), not the other way around.
        /// `RawTask.result()`, in `RequestDL`, is what actually unwraps this into the protocol
        /// existential it needs.
        package func resolvedClient() async throws -> Internals.ClientManager.Client {
            try await manager.resolvedClient(
                provider: provider,
                sessionConfiguration: configuration
            )
        }

        /// Forwards to `Internals.Client.execute(request:url:readingMode:uploadingBytes:cache:logger:)`
        /// -- kept here, with this exact signature, only because it already has direct test
        /// callers (`SessionExecutionTests`, `LocalServerConcurrencyTests`,
        /// `InternalsClientResponseReceiverTests`); the actual implementation moved onto
        /// `Internals.Client` itself in Phase 7b1 of `URLSESSION_TASK.md`, since this method's
        /// body never touched `self` (`provider`/`configuration`/`manager`) to begin with -- only
        /// `client`, taken as a parameter.
        package func execute(
            client: Internals.Client,
            request: HTTPClient.Request,
            url: String,
            readingMode: Internals.DownloadStep.ReadingMode,
            uploadingBytes: Int,
            cache: ((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?
        ) async throws -> SessionTask {
            try await client.execute(
                request: request,
                url: url,
                readingMode: readingMode,
                uploadingBytes: uploadingBytes,
                cache: cache,
                logger: logger
            )
        }
    }
}
