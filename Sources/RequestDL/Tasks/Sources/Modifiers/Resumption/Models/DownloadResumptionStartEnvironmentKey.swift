//
// See LICENSE for this package's licensing information.
//

private struct DownloadResumptionStartRequestEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: DownloadResumptionPoint? {
        nil
    }
}

extension RequestEnvironmentValues {

    /// Set by ``RequestTask/resumingDownload(from:)``; never touched directly.
    ///
    /// `RawTask` is the only thing that ever reads this: it asks the server for the rest of the
    /// resource from there, and checks the answer before anything of it is handed on. The modifier
    /// closest to the task wins, since each one sets it on the way down.
    var downloadResumptionStart: DownloadResumptionPoint? {
        get { self[DownloadResumptionStartRequestEnvironmentKey.self] }
        set { self[DownloadResumptionStartRequestEnvironmentKey.self] = newValue }
    }
}
