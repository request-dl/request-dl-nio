/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

extension Session {

    public enum DecompressionLimit {
        case none
        case ratio(Int)
        case size(Int)
    }
}

extension Session.DecompressionLimit {

    func build() -> RequestDLInternals.Session.Decompression.Limit {
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