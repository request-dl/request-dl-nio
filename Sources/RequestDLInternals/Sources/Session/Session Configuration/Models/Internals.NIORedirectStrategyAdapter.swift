//
// See LICENSE for this package's licensing information.
//

// Adapts to AsyncHTTPClient.HTTPClientRedirectStrategy: entirely .nio/.nioTransportServices-only.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOHTTP1

extension Internals {

    /// Adapts an `Internals.RedirectStrategy` to `AsyncHTTPClient.HTTPClientRedirectStrategy`,
    /// so the NIO executor can drive the exact same strategy the `URLSession` executor drives
    /// directly from its own redirect delegate.
    ///
    /// - Important: Only `url`/`method`/`headers` round-trip through `Internals.RedirectRequest`.
    /// `HTTPClientRequest.body` (along with everything else `HTTPClientRequest` carries) is
    /// taken from AsyncHTTPClient's own candidate request untouched, since
    /// `Internals.RedirectRequest` has no supported way to replace it (see
    /// ``Internals/RedirectRequest/hasBody``).
    struct NIORedirectStrategyAdapter: HTTPClientRedirectStrategy {

        // MARK: - Internal properties

        let strategy: any Internals.RedirectStrategy

        /// Rewrites each hop the way the first request was. See
        /// ``Internals/URLOverrides/rewritingRedirect(_:previous:)``.
        var urlOverrides: Internals.URLOverrides = .init()

        // MARK: - Internal methods

        func redirectDecision(for context: HTTPClientRedirectContext) throws -> HTTPClientRedirectDecision {
            let history = context.history.map(Internals.RedirectHistoryEntry.init)

            // The request this redirect answers: the one `context.response` came back for.
            let previousURL = history.last?.request.url

            var candidate = Internals.RedirectRequest(context.redirectRequest)

            // Before anything else looks at it, the strategy included: the candidate is the
            // request that would be sent, which is what `history` records of every earlier hop.
            urlOverrides.rewritingRedirect(&candidate, previous: history.last?.request)
            let rewrittenURL = candidate.url

            // AsyncHTTPClient has already stripped what it knows to strip for a redirect to
            // another origin, which does not include an explicit `Host`.
            Self.sanitize(&candidate, from: previousURL)

            let decision = try strategy.redirectDecision(
                for: .init(
                    redirectRequest: candidate,
                    // `context.response` is the response of `history`'s last entry: see
                    // `HTTPClientRedirectContext`'s own doc comment ("the full per-request
                    // `history`... including the one that produced [the response]").
                    response: .init(context.response, url: previousURL ?? ""),
                    history: history,
                    redirectCount: context.redirectCount
                )
            )

            switch decision {
            case .doNotFollow:
                return .doNotFollow
            case .follow(var redirectRequest):
                // What the strategy kept of the candidate's URL is already the destination. One it
                // wrote itself is a URL like any other `Location`; rewriting the first again would
                // send a destination through the rules a second time.
                if redirectRequest.url != rewrittenURL, let url = urlOverrides.rewriting(redirectRequest.url) {
                    redirectRequest.url = url
                }

                // Again, on what the strategy answered with: nothing it did to the URL or the
                // headers has been checked against the origin it is now going to.
                Self.sanitize(&redirectRequest, from: previousURL)

                // `.RAW(value:)` is written on the request line as it is, and this method comes from
                // a strategy: no more trusted than the caller's own.
                try Internals.MethodValidation.validate(redirectRequest.method)

                var request = context.redirectRequest
                request.url = redirectRequest.url
                request.method = .init(rawValue: redirectRequest.method)
                request.headers = redirectRequest.headers.build()
                return .follow(request)
            }
        }

        // MARK: - Private static methods

        private static func sanitize(_ request: inout Internals.RedirectRequest, from previousURL: String?) {
            // Without a previous hop there is nothing to compare against; AsyncHTTPClient always
            // supplies one, so this is only a guard.
            guard let previousURL else {
                return
            }

            Internals.RedirectSanitizer.sanitize(&request.headers, from: previousURL, to: request.url)
        }
    }
}

// MARK: - Internals.RedirectRequest extension

extension Internals.RedirectRequest {

    init(_ request: HTTPClientRequest) {
        self.init(
            url: request.url,
            method: request.method.rawValue,
            headers: Internals.HTTPHeaders(request.headers),
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

#endif
