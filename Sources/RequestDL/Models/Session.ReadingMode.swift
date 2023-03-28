/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Session {

    public enum ReadingMode {
        case length(Int)
        case separator([UInt8])
    }
}

extension Session.ReadingMode {

    func build() -> Internals.Response.ReadingMode {
        switch self {
        case .length(let length):
            return .length(length)
        case .separator(let array):
            return .separator(array)
        }
    }
}
