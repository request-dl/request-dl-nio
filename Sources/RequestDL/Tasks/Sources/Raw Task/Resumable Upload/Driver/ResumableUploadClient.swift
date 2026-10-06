//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A client that sends a request body as a resumable upload, over any other client.
///
/// Wrapped around the one `RawTask` picked for the caller's executor, so every executor gets the
/// same behaviour from the same code. A request with nothing to send is passed straight through:
/// there is nothing to resume.
struct ResumableUploadClient: RequestExecutingClient {

    // MARK: - Internal properties

    let base: any RequestExecutingClient
    let setup: ResumableUploadSetup

    // MARK: - Internal methods

    func execute(
        configuration: RequestConfiguration,
        decompression: Internals.Decompression,
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
        logger: Internals.TaskLogger?,
        transferControl: Internals.TransferControl?
    ) async throws -> SessionTask {
        guard let body = configuration.body, body.totalSize > .zero else {
            return try await base.execute(
                configuration: configuration,
                decompression: decompression,
                cache: cache,
                logger: logger,
                transferControl: transferControl
            )
        }

        // A body that is compressed as it is sent is produced here, once, so that everything that
        // follows is about the same bytes; this is also where a failure to do so is reported, like
        // any other request that is rejected before it is sent.
        let source = try await ResumableUploadSource(body)

        let execution = await ResumableUploadExecution(
            client: base,
            setup: setup,
            request: configuration,
            source: source,
            decompression: decompression,
            logger: logger,
            control: transferControl
        )

        execution.start()

        return SessionTask(seed: execution.makeSeed(), response: execution.response)
    }

    func revalidationHead(
        configuration: RequestConfiguration,
        logger: Internals.TaskLogger?
    ) async throws -> Internals.ResponseHead {
        try await base.revalidationHead(configuration: configuration, logger: logger)
    }
}
