/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct Make {

    var provider: SessionProvider?
    var configuration: Internals.Session.Configuration
    var request: Internals.Request

    init(
        configuration: Internals.Session.Configuration,
        request: Internals.Request
    ) {
        self.configuration = configuration
        self.request = request
    }
}
