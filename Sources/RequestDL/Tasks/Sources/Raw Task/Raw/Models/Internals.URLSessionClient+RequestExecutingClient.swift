//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals

/// Adapts `Internals.URLSessionClient`'s `SessionTask`-producing `execute` overloads (Phase 7b2
/// of `URLSESSION_TASK.md`) onto `RequestExecutingClient` -- the `.urlSession` counterpart to
/// `Internals.Client+RequestExecutingClient.swift`.
///
/// A request with a body always streams it (`execute(request:streaming:...)`), matching the NIO
/// backend's own uniform behavior (`RequestBody`'s streaming `AsyncSequence` conformance is used
/// unconditionally there too, with no buffered-vs-streamed distinction) -- not a heuristic this
/// conformance invents, just staying consistent with the executor it sits alongside.
extension Internals.URLSessionClient: RequestExecutingClient {

    package func execute(
        configuration: RequestConfiguration,
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
        logger: Internals.TaskLogger?
    ) async throws -> SessionTask {
        if let body = configuration.body {
            return try await execute(
                request: try configuration.buildURLRequestWithoutBody(),
                streaming: body,
                readingMode: configuration.readingMode,
                uploadingBytes: body.totalSize,
                cache: cache,
                logger: logger
            )
        }

        return try await execute(
            request: try configuration.buildURLRequestWithoutBody(),
            readingMode: configuration.readingMode,
            uploadingBytes: .zero,
            cache: cache,
            logger: logger
        )
    }

    /// - Note: `logger` is unused -- `Internals.URLSessionClient` has no logging plumbed in
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
