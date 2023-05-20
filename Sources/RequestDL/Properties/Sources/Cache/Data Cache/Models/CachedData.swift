/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct CachedData: Sendable {

    // MARK: - Public properties

    public var response: ResponseHead {
        .init(cachedResponse.response)
    }

    public var policy: DataCache.Policy.Set {
        cachedResponse.policy
    }

    public var data: Data {
        buffer.getData() ?? Data()
    }

    // MARK: - Internal properties

    let cachedResponse: CachedResponse

    let buffer: Internals.AnyBuffer

    public init<Data: DataProtocol>(
        response: ResponseHead,
        policy: DataCache.Policy.Set,
        data: Data
    ) {
        self.init(
            cachedResponse: .init(
                response: Self.internalResponse(response),
                policy: policy
            ),
            buffer: Internals.DataBuffer(data)
        )
    }

    public init(
        response: ResponseHead,
        policy: DataCache.Policy.Set,
        url: URL
    ) {
        self.init(
            cachedResponse: .init(
                response: Self.internalResponse(response),
                policy: policy
            ),
            buffer: Internals.FileBuffer(url)
        )
    }

    init(
        cachedResponse: CachedResponse,
        buffer: Internals.AnyBuffer
    ) {
        self.cachedResponse = cachedResponse
        self.buffer = buffer
    }

    // MARK: - Private static methods

    private static func internalResponse(_ response: ResponseHead) -> Internals.ResponseHead {
        .init(
            url: response.url?.absoluteString ?? "",
            status: .init(
                code: response.status.code,
                reason: response.status.reason
            ),
            version: .init(
                minor: response.version.minor,
                major: response.version.major
            ),
            headers: response.headers,
            isKeepAlive: response.isKeepAlive
        )
    }
}
