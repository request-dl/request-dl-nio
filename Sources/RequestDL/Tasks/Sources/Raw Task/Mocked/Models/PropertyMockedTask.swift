//
// See LICENSE for this package's licensing information.
//

import NIOCore

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
            requestConfiguration: requestConfiguration,
            logger: environment.logger
        )

        let cacheControl = Internals.CacheControl(
            requestConfiguration: requestConfiguration,
            dataCache: resolved.dataCache,
            logger: logger
        )

        let client = try await Internals.ClientManager.shared.client(
            provider: resolved.session.provider,
            sessionConfiguration: resolved.session.configuration
        )

        switch await cacheControl(client) {
        case .task(let task):
            return task()
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
        let eventLoopGroup = await Internals.EventLoopGroupManager.shared.provider(
            resolved.session.provider,
            with: SessionProviderOptions(
                isCompatibleWithNetworkFramework: false
            )
        )

        let downloadBuffer = await Internals.DownloadBuffer(
            readingMode: resolved.requestConfiguration.readingMode
        )

        let responseHead = mockResponseHead(resolved)

        if let cacheStream = cache?(responseHead) {
            downloadBuffer.cacheStream(cacheStream)
        }

        if let body = resolved.requestConfiguration.body {
            mockBodyResponse(
                group: eventLoopGroup,
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
            head: .constant(mockResponseHead(resolved)),
            download: downloadBuffer.stream
        )
    }

    private func mockBodyResponse(
        group eventLoopGroup: EventLoopGroup,
        buffer: Internals.DownloadBuffer,
        body: RequestBody
    ) {
        let eventLoop = eventLoopGroup.next()
        let body = body.build(eventLoop: eventLoop)

        eventLoop.execute {
            body.stream(
                .init {
                    if case .byteBuffer(let byteBuffer) = $0 {
                        // Synchronous, like the real receiver in
                        // `Internals.ClientResponseReceiver.didReceiveBodyPart`. The store is
                        // already in memory, so nothing here suspends, and appending has to
                        // stay ordered: the download queue preserves submission order and
                        // submission is synchronous.
                        buffer.append(
                            Internals.DataBuffer(
                                Internals.ByteURL(byteBuffer)
                            )
                        )
                    }

                    return eventLoop.makeSucceededVoidFuture()
                }
            ).whenComplete { result in
                // A failed stream is reported, not swallowed. `whenComplete { _ in }` closed the
                // download as though it had ended normally, so a mock configured to fail
                // mid-body looked to the caller like a short but successful response, which is
                // the one thing a mock of a failure has to get right.
                if case .failure(let error) = result {
                    buffer.failed(error)
                }

                buffer.close()
            }
        }
    }

    private func mockResponseHead(_ resolved: Resolved) -> Internals.ResponseHead {
        // Mirrors every header the resolved request would carry — `Headers`, `AcceptHeader`,
        // `Authorization`, `Payload`'s `Content-Type`/`Content-Length`, and so on — so the mocked
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
            headers: responseHeaders,
            isKeepAlive: isKeepAlive
        )
    }
}
