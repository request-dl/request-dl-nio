//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import RequestDLInternals

/// Adapts `Internals.Client`'s existing, NIO-specific `execute` methods onto
/// `RequestExecutingClient` -- Phase 7b1 of `URLSESSION_TASK.md`. No new client behavior: both
/// methods just build the `HTTPClient.Request` a `RequestConfiguration` already knows how to
/// produce (`RequestConfiguration.build(eventLoop:)`) and call straight through to what
/// `Internals.Client` already did.
extension Internals.Client: RequestExecutingClient {

    package func execute(
        configuration: RequestConfiguration,
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
        logger: Internals.TaskLogger?
    ) async throws -> SessionTask {
        try await execute(
            request: try configuration.build(eventLoop: eventLoopGroup.any()),
            url: configuration.url,
            readingMode: configuration.readingMode,
            uploadingBytes: configuration.body?.totalSize ?? .zero,
            cache: cache,
            logger: logger
        )
    }

    /// - Note: `isKeepAlive` has no equivalent on `HTTPClient.Response` and this method's own
    /// caller (`Internals.CacheControl`'s conditional-revalidation check) never reads it either
    /// way -- `true` is an inert default, matching the same call `Internals.ResponseHead.init(_
    /// response: HTTPURLResponse)` makes for the same reason on the URLSession side.
    package func revalidationHead(
        configuration: RequestConfiguration,
        logger: Internals.TaskLogger?
    ) async throws -> Internals.ResponseHead {
        let response = try await execute(
            request: try configuration.build(eventLoop: eventLoopGroup.any()),
            logger: logger
        ).response()

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
