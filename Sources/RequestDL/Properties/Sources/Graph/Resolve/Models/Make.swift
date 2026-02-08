/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct Make: Sendable {

    // MARK: - Internal properties

    var provider: SessionProvider?
    var sessionConfiguration: Internals.Session.Configuration
    var requestConfiguration: RequestConfiguration
    var cacheConfiguration: Internals.CacheConfiguration

    // MARK: - Inits

    init(
        sessionConfiguration: Internals.Session.Configuration,
        requestConfiguration: RequestConfiguration
    ) {
        self.provider = nil
        self.sessionConfiguration = sessionConfiguration
        self.requestConfiguration = requestConfiguration
        self.cacheConfiguration = .init()
    }
}
