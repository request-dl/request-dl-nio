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
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
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
                transferControl: transferControl
            )
        }

        return try await execute(
            request: try configuration.buildURLRequestWithoutBody(),
            readingMode: configuration.readingMode,
            uploadingBytes: .zero,
            decompression: decompression,
            cache: cache,
            logger: logger,
            transferControl: transferControl
        )
    }

    /// - Note: `logger` is unused: `Internals.URLSessionClient` has no logging plumbed in
    /// anywhere yet, matching every other `execute` overload on it today, none of which take one
    /// either.
    package func revalidationHead(
        configuration: RequestConfiguration,
        logger: Internals.TaskLogger?
    ) async throws -> Internals.ResponseHead {
        let (head, _) = try await execute(
            request: try configuration.buildURLRequestWithoutBody()
        )

        return head
    }
}

#endif
