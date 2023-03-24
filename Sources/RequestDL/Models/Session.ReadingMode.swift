/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

extension Session {

    public enum ReadingMode {
        case length(Int)
        case separator([UInt8])
    }
}

extension Session.ReadingMode {

    func build() -> RequestDLInternals.Response.ReadingMode {
        switch self {
        case .length(let length):
            return .length(length)
        case .separator(let array):
            return .separator(array)
        }
    }
}
