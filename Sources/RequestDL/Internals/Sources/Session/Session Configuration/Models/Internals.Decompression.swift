/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals {

    enum Decompression: Equatable {
        case disabled
        case enabled(Internals.Decompression.Limit)
    }
}

extension Internals.Decompression {

    func build() -> HTTPClient.Decompression {
        switch self {
        case .disabled:
            return .disabled
        case .enabled(let limit):
            return .enabled(limit: limit.build())
        }
    }
}
