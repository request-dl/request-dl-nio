/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals {

    enum RedirectConfiguration: Equatable {
        case disallow
        case follow(max: Int, allowCycles: Bool)
    }
}

extension Internals.RedirectConfiguration {

    func build() -> HTTPClient.Configuration.RedirectConfiguration {
        switch self {
        case .disallow:
            return .disallow
        case .follow(let max, let allowCycles):
            return .follow(max: max, allowCycles: allowCycles)
        }
    }
}
