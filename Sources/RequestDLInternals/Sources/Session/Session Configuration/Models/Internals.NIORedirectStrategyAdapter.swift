//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOHTTP1

extension Internals {

    /// Adapts an `Internals.RedirectStrategy` to `AsyncHTTPClient.HTTPClientRedirectStrategy`,
    /// so the NIO executor can drive the exact same strategy the `URLSession` executor drives
    /// directly from its own redirect delegate.
    ///
    /// - Important: Only `url`/`method`/`headers` round-trip through `Internals.RedirectRequest`.
    /// `HTTPClientRequest.body` -- along with everything else `HTTPClientRequest` carries -- is
    /// taken from AsyncHTTPClient's own candidate request untouched, since
    /// `Internals.RedirectRequest` has no supported way to replace it (see
    /// ``Internals/RedirectRequest/hasBody``).
    struct NIORedirectStrategyAdapter: HTTPClientRedirectStrategy {

        // MARK: - Internal properties

        let strategy: any Internals.RedirectStrategy

        // MARK: - Internal methods

        func redirectDecision(for context: HTTPClientRedirectContext) throws -> HTTPClientRedirectDecision {
            let history = context.history.map(Internals.RedirectHistoryEntry.init)

            let decision = try strategy.redirectDecision(
                for: .init(
                    redirectRequest: .init(context.redirectRequest),
                    // `context.response` is the response of `history`'s last entry -- see
                    // `HTTPClientRedirectContext`'s own doc comment ("the full per-request
                    // `history`... including the one that produced [the response]").
                    response: .init(context.response, url: history.last?.request.url ?? ""),
                    history: history,
                    redirectCount: context.redirectCount
                )
            )

            switch decision {
            case .doNotFollow:
                return .doNotFollow
            case .follow(let redirectRequest):
                var request = context.redirectRequest
                request.url = redirectRequest.url
                request.method = .init(rawValue: redirectRequest.method)
                request.headers = redirectRequest.headers
                return .follow(request)
            }
        }
    }
}

// MARK: - Internals.RedirectRequest extension

extension Internals.RedirectRequest {

    init(_ request: HTTPClientRequest) {
        self.init(
            url: request.url,
            method: request.method.rawValue,
            headers: request.headers,
            hasBody: request.body != nil
        )
    }
}

// MARK: - Internals.ResponseHead extension

extension Internals.ResponseHead {

    init(_ head: HTTPResponseHead, url: String) {
        self.init(
            url: url,
            status: .init(code: UInt(head.status.code), reason: head.status.reasonPhrase),
            version: .init(minor: Int(head.version.minor), major: Int(head.version.major)),
            headers: head.headers.map { .init(name: $0.name, value: $0.value) },
            isKeepAlive: head.isKeepAlive
        )
    }
}

// MARK: - Internals.RedirectHistoryEntry extension

extension Internals.RedirectHistoryEntry {

    init(_ requestResponse: HTTPClientRequestResponse) {
        self.init(
            request: .init(requestResponse.request),
            response: .init(requestResponse.responseHead, url: requestResponse.request.url)
        )
    }
}
