/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOHTTPCompression

extension Internals.Decompression {

    enum Limit: Equatable {
        case none
        case size(Int)
        case ratio(Int)
    }
}

extension Internals.Decompression.Limit {

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