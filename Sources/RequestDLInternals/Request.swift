/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

public struct Request {

    var url: String
    var method: String?
    var headers: Headers
    var body: Body?

    init(url: String) {
        self.url = url
        self.method = nil
        self.headers = .init()
        self.body = nil
    }
}

extension Request {

    func build() throws -> HTTPClient.Request {
        try HTTPClient.Request(
            url: url,
            method: method.map { .init(rawValue: $0) } ?? .GET,
            headers: .init(headers.build()),
            body: body?.build()
        )
    }
}

extension Request {

    struct Body {

        func build() -> HTTPClient.Body {
            .
        }
    }
}
