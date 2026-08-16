//
// See LICENSE for this package's licensing information.
//

extension Internals {

    package struct DownloadStep: Sendable, Equatable {
        package let head: Internals.ResponseHead
        package let bytes: Internals.AsyncBytes
    }
}
