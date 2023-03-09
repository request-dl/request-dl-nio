/*
 See LICENSE for this package's licensing information.
*/

import Foundation

class Make {

    var request: URLRequest
    let configuration: URLSessionConfiguration
    let delegate: DelegateProxy

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
