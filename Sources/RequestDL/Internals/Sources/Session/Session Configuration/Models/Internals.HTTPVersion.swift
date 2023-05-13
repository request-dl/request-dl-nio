/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals {

    enum HTTPVersion: Sendable, Hashable {
        case http1Only
        case automatic
    }
}

extension Internals.HTTPVersion {

    func build() -> HTTPClient.Configuration.HTTPVersion {
        switch self {
        case .http1Only:
            return .http1Only
        case .automatic:
            return .automatic
        }
    }
}
