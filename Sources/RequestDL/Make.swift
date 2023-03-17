/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

class Make {

    var request: HTTPRequest
    var configuration: HTTPClient.Configuration
    let delegate: DelegateProxy

    init(
        request: HTTPRequest,
        configuration: HTTPClient.Configuration,
        delegate: DelegateProxy
    ) {
        self.request = request
        self.configuration = configuration
        self.delegate = delegate
    }
}
