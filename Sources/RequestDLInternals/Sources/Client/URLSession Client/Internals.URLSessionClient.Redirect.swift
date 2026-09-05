//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Foundation
import NIOHTTP1

extension Internals.RedirectRequest {

    init(_ request: URLRequest) {
        var headers = NIOHTTP1.HTTPHeaders()

        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            headers.add(name: name, value: value)
        }

        self.init(
            url: request.url?.absoluteString ?? "",
            method: request.httpMethod ?? "GET",
            headers: headers,
            hasBody: request.httpBody != nil || request.httpBodyStream != nil
        )
    }
}

extension URLRequest {

    /// Applies a ``Internals/RedirectStrategy``'s decision on top of `self` -- everything besides
    /// `url`/`httpMethod`/headers (in particular, whatever body-related fields URLSession itself
    /// already set on the candidate request this is called on) is left untouched, mirroring how
    /// `Internals.NIORedirectStrategyAdapter` only overwrites those same three on the NIO side.
    func applyingRedirectDecision(_ redirectRequest: Internals.RedirectRequest) -> URLRequest {
        var request = self

        if let url = URL(string: redirectRequest.url) {
            request.url = url
        }

        request.httpMethod = redirectRequest.method
        request.allHTTPHeaderFields = nil

        for (name, value) in redirectRequest.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        return request
    }
}

extension URL {

    /// Whether `self` and `other` share an origin (scheme, host, and port), per RFC 6454 --
    /// mirrors `AsyncHTTPClient`'s own (internal, so not reachable from here) `URL
    /// .hasTheSameOrigin(as:)`, which the NIO executor's `followingRedirect` uses for the same
    /// cross-origin header stripping this type's own caller implements for the `URLSession`
    /// executor.
    func hasTheSameOrigin(as other: URL) -> Bool {
        host == other.host && scheme == other.scheme && port == other.port
    }
}

#endif
