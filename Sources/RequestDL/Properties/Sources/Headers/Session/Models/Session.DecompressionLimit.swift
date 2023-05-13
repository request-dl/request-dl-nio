/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOHTTPCompression

extension Session {

    public enum DecompressionLimit: Sendable, Hashable {

        case none
        case ratio(Int)
        case size(Int)

        // MARK: - Internal methods

        func build() -> Internals.Decompression.Limit {
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
