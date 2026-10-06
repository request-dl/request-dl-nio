//
// See LICENSE for this package's licensing information.
//

/// Why a download couldn't be continued from a ``DownloadResumptionPoint``.
///
/// Thrown in place of a response that isn't exactly the rest of the representation the point was
/// taken from: nothing of that response reaches the reader. Whatever it was, the download can
/// always be started again from the beginning, except for ``Reason/alreadyComplete``, which isn't a
/// failure at all.
public struct DownloadResumptionError: Error, Sendable, Hashable, CustomStringConvertible {

    /// What was wrong with the response to the request for the rest of the download.
    public enum Reason: Sendable, Hashable {

        /// The point is at the very end of the resource: there is nothing left to download. Not a
        /// failure; the file the partial download was building is complete.
        case alreadyComplete

        /// The request can't be continued at all: it isn't a `GET`, or it already carries a `Range`
        /// of its own. Nothing was sent.
        case requestNotResumable

        /// The server sent the whole resource again (a `200`): it changed since the point was taken,
        /// or it doesn't support `Range`.
        case representationChanged

        /// The range the server answered with doesn't start where the point is, or doesn't run to
        /// the end of a resource of the length it was taken from.
        case contentRangeMismatch

        /// The server answered with a validator other than the one the point carries.
        case validatorMismatch

        /// The response carries a content coding the original one didn't, so offsets in it don't
        /// mean what they did.
        case contentCoded

        /// The server can't satisfy a range at the point (a `416`), for a reason other than the
        /// download already being complete: the resource is shorter than the point.
        case unsatisfiableRange

        /// Any other status than the `206` a continuation has to be.
        case unexpectedStatus(UInt)
    }

    /// What was wrong.
    public let reason: Reason

    public var description: String {
        "The download couldn't be continued from where it stopped: \(reason)"
    }

    init(_ reason: Reason) {
        self.reason = reason
    }
}

extension DownloadResumptionError.Reason {

    /// Whether the answer is not the rest of the resource the point was taken from, as opposed to
    /// a request that couldn't be continued at all, a download that is already whole, or a server
    /// that refused: the cases in which asking for the whole resource is what is left to do.
    var isAChange: Bool {
        switch self {
        case .representationChanged, .validatorMismatch, .contentRangeMismatch, .contentCoded, .unsatisfiableRange:
            return true
        case .alreadyComplete, .requestNotResumable, .unexpectedStatus:
            return false
        }
    }
}
