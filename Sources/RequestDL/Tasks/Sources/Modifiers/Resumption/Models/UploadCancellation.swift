//
// See LICENSE for this package's licensing information.
//

/// What happens to an upload on the server when the request that is sending it is cancelled.
/// See ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)``.
public enum UploadCancellation: Sendable, Hashable {

    /// Tells the server the upload is abandoned, so it can free what it holds: an HTTP `DELETE` of
    /// the upload (the IETF draft's cancellation, tus's termination extension).
    ///
    /// Best effort, and never in the way of the cancellation itself: it is sent in the background,
    /// and the request is cancelled without waiting for the answer. It is sent only when there is
    /// something to free, which is an upload that was created and isn't complete. A failure
    /// (a server that doesn't answer, an application that is closed first) leaves the upload to
    /// expire on the server, which has to be able to do so either way.
    case terminate

    /// Leaves the upload on the server, as it is.
    case keepOnServer
}
