//
// See LICENSE for this package's licensing information.
//

extension Internals {

    enum ResponseStep: Sendable, Equatable {
        case upload(UploadStep)
        case download(DownloadStep)
    }
}
