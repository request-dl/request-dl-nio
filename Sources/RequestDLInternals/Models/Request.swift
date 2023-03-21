/*
 See LICENSE for this package's licensing information.
*/

import NIOCore
import AsyncHTTPClient

public struct Request {

    public var url: String
    public var method: String?
    public var headers: Headers
    public var body: RequestBody?

    public init(url: String) {
        self.url = url
        self.method = nil
        self.headers = .init()
        self.body = nil
    }
}

extension Request {

    func build(_ eventLoop: EventLoop) throws -> HTTPClient.Request {
        try HTTPClient.Request(
            url: url,
            method: method.map { .init(rawValue: $0) } ?? .GET,
            headers: headers.build(),
            body: body?.build(eventLoop)
        )
    }
}
