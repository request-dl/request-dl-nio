//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

struct PropertyMockedTask<Content: Property>: MockedTaskPayload {

    // MARK: - Internal properties

    let version: ResponseHead.Version
    let status: ResponseHead.Status
    let headers: HTTPHeaders
    let isKeepAlive: Bool
    let delay: UnitTime
    let content: Content

    // MARK: - Internal methods

    func result(_ environment: RequestEnvironmentValues) async throws -> AsyncResponse {
        if delay > .zero {
            try await Task.sleep(nanoseconds: UInt64(delay.nanoseconds))
        }

        let resolved = try await Resolve(
            root: content,
            environment: environment
        ).build()

        var requestConfiguration = resolved.requestConfiguration

        if [.useCachedDataOnly].contains(requestConfiguration.cacheStrategy) {
            requestConfiguration.cacheStrategy = .returnCachedDataElseLoad
        }

        let logger = Internals.TaskLogger(
            baseURL: requestConfiguration.baseURL,
            pathComponents: requestConfiguration.pathComponents,
            logger: environment.logger
        )

        let cacheControl = Internals.CacheControl(
            requestConfiguration: requestConfiguration,
            dataCache: resolved.dataCache,
            logger: logger
        )

        // Same dispatch `RawTask.resolveClient(resolved:)` does: `resolvedClient()` is the
        // executor-aware entry point, so a mock resolves through whichever backend the session
        // actually picked rather than always the NIO one. `Internals.CacheControl` only needs
        // the shared `RequestExecutingClient` existential either way.
        let client: any RequestExecutingClient

        do {
            switch try await resolved.session.resolvedClient() {
            #if canImport(NIOCore)
            case .nio(let nioClient):
                client = nioClient
            #endif
            #if canImport(Darwin)
            case .urlSession(let urlSessionClient):
                client = urlSessionClient
            #endif
            }
        } catch let error as Internals.SecureFileLoadError {
            throw SecureFileError(error)
        }

        switch await cacheControl(client) {
        case .task(let task):
            return AsyncResponse(
                seed: task.seed,
                response: task.response
            )
        case .cache(let cache):
            return try await .init(
                seed: Internals.TaskSeed.withoutCancellation,
                response: mockRequest(
                    resolved: resolved,
                    cache: cache,
                    logger: logger
                )
            )
        }
    }

    // MARK: - Private methods

    private func mockRequest(
        resolved: Resolved,
        cache: ((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
        logger: Internals.TaskLogger?
    ) async throws -> Internals.AsyncResponse {
        let downloadBuffer = await Internals.DownloadBuffer(
            readingMode: resolved.requestConfiguration.readingMode
        )

        let responseHead = mockResponseHead(resolved)

        if let cacheStream = cache?(responseHead) {
            downloadBuffer.cacheStream(cacheStream)
        }

        if let body = resolved.requestConfiguration.body {
            mockBodyResponse(
                buffer: downloadBuffer,
                body: body
            )
        } else {
            downloadBuffer.close()
        }

        return Internals.AsyncResponse(
            logger: logger,
            uploadingBytes: .zero,
            upload: .empty(),
            decompressionDispatch: .skip,
            head: .constant(mockResponseHead(resolved)),
            download: downloadBuffer.stream
        )
    }

    /// Drives `body` into `buffer`, executor-agnostically: `RequestBody`'s internal
    /// `bytesSequence` already yields `Internals.Bytes` chunks portably (no
    /// `EventLoopGroup`/`HTTPClient.Body` needed the way an older revision of this method
    /// required), so there's nothing NIO-specific left to bridge here for either executor.
    /// `bytesSequence`, not the public, `Data`-yielding `AsyncSequence` conformance: the public
    /// one forces every chunk through `Internals.Bytes.asData()` before handing it back, a
    /// conversion `Internals.ByteURL.replace(with:)`'s own `Internals.Bytes` overload has no use
    /// for and would otherwise pay for nothing, exactly the round trip `RequestBody
    /// .connect(writer:body:eventLoop:)` already avoids the same way on the `.nio` side.
    ///
    /// - Important: One sequential `for try await` loop inside a single `Task`, not chunks
    /// dispatched independently. `buffer.append` has to see chunks in order, and awaiting each
    /// one before appending it, in the same task, is what guarantees that. It is the same requirement
    /// `Internals.ClientResponseReceiver.didReceiveBodyPart`'s own synchronous-append discipline
    /// exists for, just satisfied here by sequencing instead of by staying off a detached task.
    private func mockBodyResponse(
        buffer: Internals.DownloadBuffer,
        body: RequestBody
    ) {
        _Concurrency.Task {
            do {
                for try await chunk in body.bytesSequence {
                    let byteURL = Internals.ByteURL()
                    byteURL.replace(with: chunk)
                    // The `async` overload, not the synchronous one `Internals
                    // .ClientResponseReceiver` needs. Safe here because this whole loop is one
                    // sequential path in a single `Task`, not chunks dispatched independently
                    // from a delegate callback, so there is nothing else racing to append out of
                    // order while this `await` suspends.
                    buffer.append(await Internals.DataBuffer(byteURL))
                }
            } catch {
                buffer.failed(error)
            }

            buffer.close()
        }
    }

    private func mockResponseHead(_ resolved: Resolved) -> Internals.ResponseHead {
        // Mirrors every header the resolved request would carry, `Headers`, `AcceptHeader`,
        // `Authorization`, `Payload`'s `Content-Type`/`Content-Length`, and so on, so the mocked
        // response doubles as a way to inspect exactly what the request would have looked like.
        // `headers` overlays on top, for anything that isn't part of the request itself.
        var responseHeaders = resolved.requestConfiguration.headers
            .merging(headers) { _, theirs in theirs }

        if let method = resolved.requestConfiguration.method {
            responseHeaders.set(name: "rdl-request-method", value: method)
        }

        return .init(
            url: resolved.requestConfiguration.url,
            status: .init(code: status.code, reason: status.reason),
            version: .init(minor: version.minor, major: version.major),
            headers: responseHeaders.map { Internals.ResponseHead.HeaderField(name: $0.name, value: $0.value) },
            isKeepAlive: isKeepAlive
        )
    }
}
