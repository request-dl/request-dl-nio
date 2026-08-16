//
// See LICENSE for this package's licensing information.
//

extension Internals {

    package struct UploadStep: Sendable, Equatable {
        package let chunkSize: Int
        package let totalSize: Int
    }
}
