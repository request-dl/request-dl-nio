/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

struct Make: Sendable {

    // MARK: - Internal properties

    var provider: SessionProvider?
    var logger: Logger?
    var configuration: Internals.Session.Configuration
    var request: Internals.Request
    var cacheConfiguration: Internals.CacheConfiguration

    // MARK: - Inits

    init(
        configuration: Internals.Session.Configuration,
        request: Internals.Request
    ) {
        self.provider = nil
        self.logger = nil
        self.configuration = configuration
        self.request = request
        self.cacheConfiguration = .init()
    }
}
