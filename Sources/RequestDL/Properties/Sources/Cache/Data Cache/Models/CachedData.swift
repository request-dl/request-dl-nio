/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A struct representing cached data with associated metadata.
 */
public struct CachedData: Sendable {

    // MARK: - Public properties

    /**
     The response head associated with the cached data.
     */
    public var response: ResponseHead {
        .init(cachedResponse.response)
    }

    /**
     The cache policy associated with the cached data.
     */
    public var policy: DataCache.Policy.Set {
        cachedResponse.policy
    }

    /**
     The actual data stored in the cache.
     */
    public var data: Data {
        buffer.getData() ?? Data()
    }

    // MARK: - Internal properties

    let cachedResponse: CachedResponse

    let buffer: Internals.AnyBuffer

    /**
     Initializes with the provided response head, cache policy, and data.

     - Parameters:
        - response: The response head associated with the cached data.
        - policy: The cache policy associated with the cached data.
        - data: The data to be cached.
     */
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

    /**
     Initializes with the provided response head, cache policy, and file URL.

     - Parameters:
        - response: The response head associated with the cached data.
        - policy: The cache policy associated with the cached data.
        - url: The file URL representing the location of the cached data.
     */
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
