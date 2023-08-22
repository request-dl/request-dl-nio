/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct UploadStep: Sendable, Equatable {
        let chunkSize: Int
        let totalSize: Int
    }
}
