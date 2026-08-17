//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient

extension Internals {

    package enum Decompression: Sendable, Hashable {

        case disabled
        case enabled(Internals.Decompression.Limit)

        // MARK: - Internal methods

        package func build() -> HTTPClient.Decompression {
            switch self {
            case .disabled:
                return .disabled
            case .enabled(let limit):
                return .enabled(limit: limit.build())
            }
        }
    }
}
