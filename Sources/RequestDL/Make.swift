/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

class Make {

    var request: Request
    var configuration: RequestDLInternals.Session.Configuration

    init(
        request: Request,
        configuration: RequestDLInternals.Session.Configuration
    ) {
        self.request = request
        self.configuration = configuration
    }
}
