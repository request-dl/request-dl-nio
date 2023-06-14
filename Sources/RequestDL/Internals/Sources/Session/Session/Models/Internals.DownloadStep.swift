/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct DownloadStep: Sendable, Equatable {
        let head: Internals.ResponseHead
        let bytes: Internals.AsyncBytes
    }
}
