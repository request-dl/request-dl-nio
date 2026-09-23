//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

struct Make: Sendable {

    // MARK: - Internal properties

    var provider: SessionProvider?
    var sessionConfiguration: Internals.Session.Configuration
    var requestConfiguration: RequestConfiguration
    var cacheConfiguration: Internals.CacheConfiguration

    /// Whether the request asked to follow the system's proxy configuration.
    ///
    /// Build time intent, not session identity: the proxy it resolves to is what ends up in
    /// `sessionConfiguration`, and that is what the client cache keys on.
    var resolvesSystemProxy: Bool

    /// Rules accumulated by every declared `URLOverride`, in declaration order.
    ///
    /// Matched against the final `baseURL`/`pathComponents` in `Resolve.build()`, once every
    /// property (including whichever `BaseURL` wins) has contributed — matching here, while the
    /// tree is still being walked, could still miss a `BaseURL` or `Path` declared later.
    var urlOverrides: [URLOverrideRule]

    /// Url-encoded `Payload` fields accumulated by every declared `Payload`, in declaration
    /// order, whose query-vs-body placement is still pending.
    ///
    /// Resolved by `Resolve.build()`, once every property (including whichever `RequestMethod`
    /// wins) has contributed — deciding here, while the tree is still being walked, could still
    /// miss a `RequestMethod` declared later. See `PendingURLEncodedPayload`'s own doc comment.
    var pendingURLEncodedPayloads: [PendingURLEncodedPayload]

    // MARK: - Inits

    init(
        sessionConfiguration: Internals.Session.Configuration,
        requestConfiguration: RequestConfiguration
    ) {
        self.provider = nil
        self.sessionConfiguration = sessionConfiguration
        self.requestConfiguration = requestConfiguration
        self.cacheConfiguration = .init()
        self.resolvesSystemProxy = false
        self.urlOverrides = []
        self.pendingURLEncodedPayloads = []
    }
}
