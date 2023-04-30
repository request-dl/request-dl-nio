/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct Make {

    var request: Internals.Request
    var configuration: Internals.Session.Configuration

    init(
        request: Internals.Request,
        configuration: Internals.Session.Configuration
    ) {
        self.request = request
        self.configuration = configuration
    }
}
