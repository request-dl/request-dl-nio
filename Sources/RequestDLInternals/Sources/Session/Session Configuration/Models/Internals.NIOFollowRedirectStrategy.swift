//
// See LICENSE for this package's licensing information.
//

// Adapts to AsyncHTTPClient.HTTPClientRedirectStrategy: entirely .nio/.nioTransportServices-only.
#if canImport(NIOCore)

import AsyncHTTPClient

extension Internals {

    /// AsyncHTTPClient's own `.follow(max:allowCycles:)`, reproduced as a strategy so the one thing
    /// it gets wrong for this package, an explicit `Host` header replayed on a redirect to another
    /// origin, can be put right.
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

        // MARK: - Internal methods

        func redirectDecision(for context: HTTPClientRedirectContext) throws -> HTTPClientRedirectDecision {
            // `.follow` tracks the URLs visited so far, the first request's included, and refuses
            // once there are more than `max` of them. `history` holds exactly those requests.
            guard context.history.count <= max else {
                throw HTTPClientError.redirectLimitReached
            }

            var request = context.redirectRequest

            guard allowCycles || !context.history.contains(where: { $0.request.url == request.url }) else {
                throw HTTPClientError.redirectCycleDetected
            }

            if let previousURL = context.history.last?.request.url,
                !Internals.RedirectSanitizer.isSameOrigin(previousURL, request.url)
            {
                request.headers.remove(name: "Host")
            }

            return .follow(request)
        }
    }
}

#endif
