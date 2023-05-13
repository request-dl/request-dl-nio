/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    enum Response: Sendable, Equatable {
        case upload(Int)
        case download(Internals.ResponseHead, Internals.AsyncBytes)
    }
}
