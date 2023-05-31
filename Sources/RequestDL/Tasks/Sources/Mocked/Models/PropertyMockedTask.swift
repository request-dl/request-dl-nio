/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif
import NIOCore

struct PropertyMockedTask<Content: Property>: MockedTaskPayload {

    // MARK: - Internal properties

    let version: ResponseHead.Version
    let status: ResponseHead.Status
    let isKeepAlive: Bool
    let content: Content

    // MARK: - Internal methods

    func result() async throws -> AsyncResponse {
        let resolved = try await Resolve(content).build()

        var request = resolved.request

        if [.returnCachedDataElseLoad, .reloadAndValidateCachedData].contains(request.cacheStrategy) {
            request.cacheStrategy = .useCachedDataOnly
        }

        let cacheControl = Internals.CacheControl(
            request: request,
            dataCache: resolved.dataCache
        )

        let client = try await Internals.ClientManager.shared.client(
            provider: resolved.session.provider,
            configuration: resolved.session.configuration
        )

        switch await cacheControl(client) {
        case .task(let task):
            return task()
        case .cache(let cache):
            return try await .init(
                seed: .withoutCancellation,
                response: mockRequest(
                    resolved: resolved,
                    cache: cache
                )
            )
        }
    }

    // MARK: - Private methods

    private func mockRequest(
        resolved: Resolved,
        cache: ((Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?
    ) async throws -> Internals.AsyncResponse {
        let eventLoopGroup = await Internals.EventLoopGroupManager.shared.provider(resolved.session.provider)

        var downloadBuffer = Internals.DownloadBuffer(readingMode: resolved.request.readingMode)

        let responseHead = mockResponseHead(resolved)

        if let cacheStream = cache?(responseHead) {
            downloadBuffer.cacheStream(cacheStream)
        }

        if let body = resolved.request.body {
            mockBodyResponse(
                group: eventLoopGroup,
                buffer: downloadBuffer,
                body: body
            )
        } else {
            downloadBuffer.close()
        }

        return Internals.AsyncResponse(
            upload: .empty(),
            head: .constant(mockResponseHead(resolved)),
            download: downloadBuffer.stream
        )
    }

    private func mockBodyResponse(
        group eventLoopGroup: EventLoopGroup,
        buffer: Internals.DownloadBuffer,
        body: Internals.Body
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
        .init(
            url: resolved.request.url,
            status: .init(code: status.code, reason: status.reason),
            version: .init(minor: version.minor, major: version.major),
            headers: resolved.request.headers,
            isKeepAlive: isKeepAlive
        )
    }
}
