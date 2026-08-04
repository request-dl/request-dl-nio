//
// See LICENSE for this package's licensing information.
//

/// Represents a step in the response process.
///
/// - Note: `Sendable` as of 4.0. Both payloads already were, and this is the `Element` of
/// ``AsyncResponse``, which is a `Sendable` `AsyncSequence`, so its element crossing isolation
/// boundaries is the normal case rather than the exception.
public enum ResponseStep: Sendable, Hashable {
    /// An upload step.
    case upload(UploadStep)
    /// A download step.
    case download(DownloadStep)
}
