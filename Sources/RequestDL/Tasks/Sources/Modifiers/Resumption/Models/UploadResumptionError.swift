//
// See LICENSE for this package's licensing information.
//

/// Why an upload that was made resumable (see ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)``)
/// couldn't be carried through.
///
/// A failure of the connection that ends the last attempt is thrown as it is: these are the ones
/// that are about the upload itself.
public struct UploadResumptionError: Error, Sendable, Hashable, CustomStringConvertible {

    /// What went wrong with the upload.
    public enum Reason: Sendable, Hashable {

        /// The server answered the request that creates the upload without saying where it is, so
        /// it doesn't speak the protocol the upload was asked to use.
        case notSupported

        /// The server no longer has the upload (it expired, or was removed), so there is nothing
        /// to continue. The status is the one it answered with.
        case uploadLost(status: UInt)

        /// The server refused to say how much of the upload it holds. The status is the one it
        /// answered with.
        case offsetRejected(status: UInt)

        /// The server says it holds more of the upload than the body has.
        case offsetBeyondLength(offset: Int64, length: Int64)

        /// The server holds the whole body, but the response to the request that completed it never
        /// arrived, and the protocol has no way to get it again. The IETF draft's response is the
        /// application's, so nothing else the server says takes its place; tus's carries nothing
        /// but the offset, so there it doesn't come to this.
        case completedWithoutResponse

        /// The server keeps disagreeing about where to continue from.
        case conflictingOffsets

        /// The server kept answering "not now" (a `5xx`, `408`, `425` or `429`) every time it was
        /// asked how much of the upload it holds, until the attempts ran out. The status is the
        /// last one it answered with.
        case serverUnavailable(status: UInt)
    }

    /// What went wrong.
    public let reason: Reason

    public var description: String {
        "The upload couldn't be continued: \(reason)"
    }

    init(_ reason: Reason) {
        self.reason = reason
    }
}
