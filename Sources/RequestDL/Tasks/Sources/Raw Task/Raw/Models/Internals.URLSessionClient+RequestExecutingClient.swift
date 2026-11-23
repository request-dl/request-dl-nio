//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals

/// Adapts `Internals.URLSessionClient`'s `SessionTask`-producing `execute` overloads onto
/// `RequestExecutingClient`: the `.urlSession` counterpart to
/// `Internals.Client+RequestExecutingClient.swift`.
///
/// A request with a body always goes through `execute(request:streaming:...)`, matching the NIO
/// backend's own uniform behavior (`RequestBody`'s streaming `AsyncSequence` conformance is used
/// unconditionally there too, with no buffered-vs-streamed distinction at this layer).
///
/// What that call actually uploads *from* is `Internals.URLSessionClient`'s own decision: memory,
/// a fresh temp file, or, via `existingUploadFile: body.wholeFileURL` below, a `Payload(url:)`
/// body's own file directly, skipping a redundant copy. See `Internals.URLSessionUploadFile` for
/// that logic; this conformance only forwards the hint.
extension Internals.URLSessionClient: RequestExecutingClient {

    /// With a `transferControl`, the materialized body reaches the wire through
    /// `Internals.URLSessionUploadBodyPump` rather than `httpBody`/a file stream, which is what
    /// lets a suspension pause it; everything else is `Internals.URLSessionClient`'s own business.
    package func execute(
        configuration: RequestConfiguration,
        decompression: Internals.Decompression,
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)?,
        logger: Internals.TaskLogger?,
        transferControl: Internals.TransferControl?
    ) async throws -> SessionTask {
        if let body = configuration.body {
            return try await execute(
                request: try configuration.buildURLRequestWithoutBody(),
                streaming: body.bytesSequence,
                readingMode: configuration.readingMode,
                uploadingBytes: body.totalSize,
                decompression: decompression,
                cache: cache,
                logger: logger,
                existingUploadFile: body.wholeFileURL,
                transferControl: transferControl,
                cookies: configuration.cookies
            )
        }

        return try await execute(
            request: try configuration.buildURLRequestWithoutBody(),
            readingMode: configuration.readingMode,
            uploadingBytes: .zero,
            decompression: decompression,
            cache: cache,
            logger: logger,
            transferControl: transferControl,
            cookies: configuration.cookies
        )
    }

    /// - Note: `logger` is unused: `Internals.URLSessionClient` has no logging plumbed in
    /// anywhere yet, matching every other `execute` overload on it today, none of which take one
    /// either.
    package func revalidationHead(
        configuration: RequestConfiguration,
        logger: Internals.TaskLogger?,
        metrics: Internals.RequestMetricsCollector?
    ) async throws -> Internals.ResponseHead {
        var request = try configuration.buildURLRequestWithoutBody()

        // The conditional request says what the request it revalidates said, so the server answers
        // it for the same representation: `Vary: Accept-Encoding` with a strong ETag per
        // representation would otherwise never match one sent with CFNetwork's own default, and
        // every revalidation would be a miss. Unless the caller wrote one, which that request
        // carried as it is.
        if let acceptEncoding, request.value(forHTTPHeaderField: "Accept-Encoding") == nil {
            request.setValue(acceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        }

        let (head, _) = try await execute(
            request: request,
            metrics: metrics,
            metricsSource: .revalidation,
            cookies: configuration.cookies
        )

        return head
    }
}

#endif
