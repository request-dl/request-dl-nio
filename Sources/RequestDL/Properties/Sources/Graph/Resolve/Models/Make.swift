//
// See LICENSE for this package's licensing information.
//

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
    }
}
