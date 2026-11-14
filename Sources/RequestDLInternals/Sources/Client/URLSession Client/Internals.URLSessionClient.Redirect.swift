//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Foundation

extension Internals.RedirectRequest {

    init(_ request: URLRequest) {
        var headers = Internals.HTTPHeaders()

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

    /// Applies a ``Internals/RedirectStrategy``'s decision on top of `self`: everything besides
    /// `url`/`httpMethod`/headers (in particular, whatever body-related fields URLSession itself
    /// already set on the candidate request this is called on) is left untouched, mirroring how
    /// `Internals.NIORedirectStrategyAdapter` only overwrites those same three on the NIO side.
    ///
    /// - Throws: ``Internals/RedirectError`` (``Internals/RedirectError/Reason/invalidURL(_:)``) if the decision's URL
    ///   doesn't parse. Keeping the request's own URL instead would follow the `Location` the
    ///   server sent, a destination the strategy had just decided against.
    func applyingRedirectDecision(_ redirectRequest: Internals.RedirectRequest) throws -> URLRequest {
        var request = self

        guard let url = URL(string: redirectRequest.url) else {
            throw Internals.RedirectError(.invalidURL(redirectRequest.url))
        }

        request.url = url

        request.httpMethod = redirectRequest.method
        request.allHTTPHeaderFields = nil

        for (name, value) in redirectRequest.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        return request
    }
}

#endif
