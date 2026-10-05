//
// See LICENSE for this package's licensing information.
//

/// Why a resumable upload could not be carried through.
///
/// A failure of the connection that ends the last attempt is rethrown as it is; these are the
/// ones that are about the upload itself.
struct ResumableUploadError: Error, Hashable {

    enum Reason: Sendable, Hashable {

        /// The server answered the request that creates the upload without saying where it is, so
        /// it doesn't speak the protocol the upload was asked to use.
        case notSupported

        /// The server no longer has the upload (it expired, or was removed), so there is nothing
        /// to continue.
        case uploadLost(status: UInt)

        /// The server refused to say how much of the upload it holds.
        case offsetRejected(status: UInt)

        /// The server says it holds more of the upload than the body has.
        case offsetBeyondLength(offset: Int64, length: Int64)

        /// The server holds the whole body, but the response to the request that completed it
        /// never arrived, and the protocol has no way to get it again.
        case completedWithoutResponse

        /// The server keeps disagreeing about where to continue from.
        case conflictingOffsets
    }

    let reason: Reason
}

/// A response that means "not now", rather than "never": the same as a lost connection to whatever
/// is retrying.
struct ResumableUploadTransientResponse: Error {
    let status: UInt
}
