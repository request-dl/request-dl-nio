//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import AsyncHTTPClient
import RequestDLInternals

/// Adapts `Internals.Client`'s existing, NIO-specific `execute` methods onto
/// `RequestExecutingClient`. No new client behavior: both methods just build the
/// `HTTPClient.Request` a `RequestConfiguration` already knows how to produce
/// (`RequestConfiguration.build(eventLoop:)`) and call straight through to what
/// `Internals.Client` already did.
extension Internals.Client: RequestExecutingClient {

    /// With a `transferControl`, the request body streams through its gate (paused between
    /// chunks while suspended), and the rest is `Internals.Client`'s own business.
    package func execute(
        configuration: RequestConfiguration,
        decompression: Internals.Decompression,
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)?,
        logger: Internals.TaskLogger?,
        transferControl: Internals.TransferControl?
    ) async throws -> SessionTask {
        try await execute(
            request: try announcingAcceptEncoding(
                in: configuration
            ).build(
                eventLoop: eventLoopGroup.any(),
                uploadGate: transferControl?.uploadGate
            ),
            url: configuration.url,
            readingMode: configuration.readingMode,
            uploadingBytes: configuration.body?.totalSize ?? .zero,
            decompression: decompression,
            cache: cache,
            logger: logger,
            transferControl: transferControl,
            cookies: configuration.cookies
        )
    }

    /// `configuration` saying what this client's session was configured to decode, unless it
    /// already says what it accepts.
    ///
    /// The conditional request of a revalidation says it too, so the server answers it for the
    /// same representation it sends the response in.
    private func announcingAcceptEncoding(in configuration: RequestConfiguration) -> RequestConfiguration {
        guard let acceptEncoding, !configuration.headers.contains(name: "Accept-Encoding") else {
            return configuration
        }

        var configuration = configuration
        configuration.headers.add(name: "Accept-Encoding", value: acceptEncoding)
        return configuration
    }

    /// - Note: `isKeepAlive` has no equivalent on `HTTPClient.Response` and this method's own
    /// caller (`Internals.CacheControl`'s conditional-revalidation check) never reads it either
    /// way: `true` is an inert default, matching the same call `Internals.ResponseHead.init(_
    /// response: HTTPURLResponse)` makes for the same reason on the URLSession side.
    package func revalidationHead(
        configuration: RequestConfiguration,
        logger: Internals.TaskLogger?,
        metrics: Internals.RequestMetricsCollector?
    ) async throws -> Internals.ResponseHead {
        let request = try announcingAcceptEncoding(in: configuration).build(eventLoop: eventLoopGroup.any())

        // A request that nobody collects metrics for still goes through the wrapper, into a collector
        // of its own that is dropped: one path to maintain and to test, instead of two.
        let accumulator = Internals.MetricsCollectingAccumulator(
            request: request,
            metrics: metrics ?? Internals.RequestMetricsCollector(),
            source: .revalidation,
            cookies: configuration.cookies
        )

        let task = try await execute(request: request, delegate: accumulator, logger: logger)
        let response: HTTPClient.Response

        do {
            response = try await task.response()
        } catch {
            // A `HEAD` is answered without a body, which is not a reason for it to fail when it
            // says `Content-Encoding: gzip`.
            response = try accumulator.recovering(from: error)
        }

        return Internals.ResponseHead(
            url: configuration.url,
            status: .init(
                code: response.status.code,
                reason: response.status.reasonPhrase
            ),
            version: .init(
                minor: response.version.minor,
                major: response.version.major
            ),
            headers: response.headers.map {
                .init(name: $0.name, value: $0.value)
            },
            isKeepAlive: true
        )
    }
}

#endif
