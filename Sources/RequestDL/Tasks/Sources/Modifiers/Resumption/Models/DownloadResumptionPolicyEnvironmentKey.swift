//
// See LICENSE for this package's licensing information.
//

private struct DownloadResumptionPolicyRequestEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: DownloadResumptionPolicy {
        .disabled
    }
}

extension RequestEnvironmentValues {

    /// Set by ``RequestTask/resumingDownloads(_:)``; never touched directly.
    ///
    /// `RawTask` is the only thing that ever reads this, when it gives the execution its transfer
    /// control. The modifier closest to the task wins, since each one sets it on the way down.
    var downloadResumptionPolicy: DownloadResumptionPolicy {
        get { self[DownloadResumptionPolicyRequestEnvironmentKey.self] }
        set { self[DownloadResumptionPolicyRequestEnvironmentKey.self] = newValue }
    }
}
