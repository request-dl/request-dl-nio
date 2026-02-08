/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

struct PropertyMockedTask<Content: Property>: MockedTaskPayload {

    // MARK: - Internal properties

    let version: ResponseHead.Version
    let status: ResponseHead.Status
    let isKeepAlive: Bool
    let content: Content

    // MARK: - Internal methods

    func result(_ environment: RequestEnvironmentValues) async throws -> AsyncResponse {
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

        var downloadBuffer = Internals.DownloadBuffer(
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
        let body = body.build()

        eventLoop.execute {
            body.stream(.init {
                if case .byteBuffer(let byteBuffer) = $0 {
                    buffer.append(Internals.DataBuffer(
                        Internals.ByteURL(byteBuffer)
                    ))
                }

                return eventLoop.makeSucceededVoidFuture()
            }).whenComplete { _ in
                buffer.close()
            }
        }
    }

    private func mockResponseHead(_ resolved: Resolved) -> Internals.ResponseHead {
        var headers = resolved.requestConfiguration.headers

        if let method = resolved.requestConfiguration.method {
            headers.set(name: "rdl-request-method", value: method)
        }

        return .init(
            url: resolved.requestConfiguration.url,
            status: .init(code: status.code, reason: status.reason),
            version: .init(minor: version.minor, major: version.major),
            headers: resolved.requestConfiguration.headers,
            isKeepAlive: isKeepAlive
        )
    }
}
