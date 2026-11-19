//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A client whose conditional revalidation request is bounded by the idle deadline of the
/// execution it is part of.
///
/// That request goes out before there is a request for the deadline to cancel, so a server that
/// takes it and never answers would leave the execution waiting for good. Only that request is
/// bounded: what `Internals.CacheControl` does around it (the cache's own reads and writes) is
/// not the server's silence, and a deadline that cancelled it would leave an entry half written.
struct IdleBoundedClient: RequestExecutingClient {

    // MARK: - Private properties

    private let base: any RequestExecutingClient
    private let idle: Internals.IdleDeadline

    // MARK: - Inits

    init(_ base: any RequestExecutingClient, idle: Internals.IdleDeadline) {
        self.base = base
        self.idle = idle
    }

    // MARK: - Internal methods

    func execute(
        configuration: RequestConfiguration,
        decompression: Internals.Decompression,
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)?,
        logger: Internals.TaskLogger?,
        transferControl: Internals.TransferControl?
    ) async throws -> SessionTask {
        try await base.execute(
            configuration: configuration,
            decompression: decompression,
            cache: cache,
            logger: logger,
            transferControl: transferControl
        )
    }

    func revalidationHead(
        configuration: RequestConfiguration,
        logger: Internals.TaskLogger?,
        metrics: Internals.RequestMetricsCollector?
    ) async throws -> Internals.ResponseHead {
        let base = base

        return try await idle.bounding {
            try await base.revalidationHead(configuration: configuration, logger: logger, metrics: metrics)
        }
    }
}
