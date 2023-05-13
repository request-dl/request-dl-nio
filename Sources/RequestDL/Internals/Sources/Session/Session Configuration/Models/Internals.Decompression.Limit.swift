/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOHTTPCompression

extension Internals.Decompression {

    enum Limit: Sendable, Hashable {

        case none
        case size(Int)
        case ratio(Int)

        // MARK: - Internal methods

        func build() -> NIOHTTPDecompression.DecompressionLimit {
            switch self {
            case .none:
                return .none
            case .ratio(let value):
                return .ratio(value)
            case .size(let value):
                return .size(value)
            }
        }
    }
}
