//
// See LICENSE for this package's licensing information.
//

// Adapts to AsyncHTTPClient.HTTPClientRedirectStrategy: entirely .nio/.nioTransportServices-only.
#if canImport(NIOCore)

import AsyncHTTPClient

extension Internals {

    /// AsyncHTTPClient's own `.follow(max:allowCycles:)`, reproduced as a strategy so the two things
    /// it gets wrong for this package can be put right: an explicit `Host` header replayed on a
    /// redirect to another origin, and the credentials a `URLOverride` rule would carry to an origin
    /// AsyncHTTPClient never compared the request with.
    ///
    /// `.follow` rewrites the request through AsyncHTTPClient's `transformRequestForRedirect`,
    /// which strips `Origin`/`Cookie`/`Authorization`/`Proxy-Authorization` for another origin
    /// and has no hook to add to that list. `.strategy` hands over the very same rewritten
    /// candidate (its `retainHTTPMethodAndBodyOn30{1,2}` flags are `.follow`'s defaults), so the
    /// only differences left are the ones this type makes up for itself:
    ///
    /// - the limit is `max` redirects followed, failing with
    ///   `HTTPClientError.redirectLimitReached` for the next one, and
    /// - a URL already visited fails with `HTTPClientError.redirectCycleDetected`, unless
    ///   `allowCycles` says otherwise,
    ///
    /// both in that order and both the errors `.follow` fails with, so `RedirectError.translating`
    /// reports them the same way as before.
    struct NIOFollowRedirectStrategy: HTTPClientRedirectStrategy {

        // MARK: - Internal properties

        let max: Int
        let allowCycles: Bool
        /// Rewrites each hop the way the first request was, before it is checked or followed. See
        /// ``Internals/URLOverrides/rewritingRedirect(_:previous:)``.
        var urlOverrides: Internals.URLOverrides = .init()

        // MARK: - Internal methods

        func redirectDecision(for context: HTTPClientRedirectContext) throws -> HTTPClientRedirectDecision {
            // `.follow` tracks the URLs visited so far, the first request's included, and refuses
            // once there are more than `max` of them. `history` holds exactly those requests.
            guard context.history.count <= max else {
                throw HTTPClientError.redirectLimitReached
            }

            var request = context.redirectRequest

            // First, so that the cycle check below compares the URL that would actually be
            // requested with the ones that were, and not a `Location` that spells the host an
            // override stands in for.
            if !urlOverrides.isEmpty {
                var candidate = Internals.RedirectRequest(request)
                let previous = context.history.last.map { Internals.RedirectRequest($0.request) }

                urlOverrides.rewritingRedirect(&candidate, previous: previous)

                request.url = candidate.url
                request.headers = candidate.headers.build()
            }

            guard allowCycles || !context.history.contains(where: { $0.request.url == request.url }) else {
                throw HTTPClientError.redirectCycleDetected
            }

            // On the final URL, which is not the one AsyncHTTPClient decided what to take off for:
            // it compared the previous hop with the `Location`, and a rule can map a `Location` on
            // the same origin to another one. This takes off everything a redirect to another
            // origin must not carry, `Host` included.
            if let previousURL = context.history.last?.request.url {
                var headers = Internals.HTTPHeaders(request.headers)
                Internals.RedirectSanitizer.sanitize(&headers, from: previousURL, to: request.url)
                request.headers = headers.build()
            }

            return .follow(request)
        }
    }
}

#endif
