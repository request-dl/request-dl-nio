/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct Make {

    var request: URLRequest
    let configuration: URLSessionConfiguration
    let delegate: DelegateProxy

    var isInsideSecureConnection = false

    init(
        request: URLRequest,
        configuration: URLSessionConfiguration,
        delegate: DelegateProxy
    ) {
        self.request = request
        self.configuration = configuration
        self.delegate = delegate
    }
}
