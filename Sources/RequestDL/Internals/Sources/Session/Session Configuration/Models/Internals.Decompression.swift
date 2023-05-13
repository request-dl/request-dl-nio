/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals {

    enum Decompression: Sendable, Hashable {

        case disabled
        case enabled(Internals.Decompression.Limit)

        // MARK: - Internal methods

        func build() -> HTTPClient.Decompression {
            switch self {
            case .disabled:
                return .disabled
            case .enabled(let limit):
                return .enabled(limit: limit.build())
            }
        }
    }
}
