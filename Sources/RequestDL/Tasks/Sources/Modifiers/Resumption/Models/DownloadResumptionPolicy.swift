//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Whether, and how, a download that loses its connection mid-body carries on from where it
/// stopped instead of failing. See ``RequestTask/resumingDownloads(_:)``.
///
/// Reconnecting sends a new request for the rest of the body (an HTTP `Range` request, RFC 9110
/// §14) and splices it onto what was already delivered. That is only ever done when it is safe to:
///
/// - the request is a `GET` without a `Range` of its own;
/// - the original response is a `200` without a content coding (`Content-Encoding`);
/// - the response carries a *strong* validator: a strong `ETag`, or, without any `ETag`, a strong
///   `Last-Modified`. The continuation asks with `If-Range`, so a resource that changed in the
///   meantime is never spliced onto the bytes of its previous version.
///
/// A download that doesn't meet these fails on a lost connection exactly as it does without a
/// policy. A continuation that isn't exactly the rest of the same representation (the resource
/// changed, or the server ignores `Range`) fails the download with an error, and not one byte of
/// it reaches the reader.
public struct DownloadResumptionPolicy: Sendable, Hashable {

    // MARK: - Internal properties

    let resumption: Internals.DownloadResumptionPolicy?

    // MARK: - Inits

    private init(_ resumption: Internals.DownloadResumptionPolicy?) {
        self.resumption = resumption
    }

    // MARK: - Public static methods

    /// A lost connection fails the download. What every download does unless it opts in.
    public static let disabled = DownloadResumptionPolicy(nil)

    /// Reconnects a download whose connection is lost mid-body, when it is safe to.
    ///
    /// - Parameters:
    ///   - maximumAttemptsWithoutProgress: How many reconnection attempts in a row may fail
    ///   without a single new byte arriving before the download fails for good. Any progress
    ///   starts the count over, so a long download over a flaky network isn't capped, while a
    ///   server that keeps failing is given up on. Values below one are treated as one.
    ///   - delay: Seconds to wait before each attempt. Negative values are treated as zero.
    public static func enabled(
        maximumAttemptsWithoutProgress: Int = 3,
        delay: Double = 1
    ) -> DownloadResumptionPolicy {
        let nanoseconds = (max(delay, .zero) * 1_000_000_000).rounded()

        return DownloadResumptionPolicy(
            Internals.DownloadResumptionPolicy(
                maximumAttemptsWithoutProgress: max(1, maximumAttemptsWithoutProgress),
                delay: nanoseconds >= Double(UInt64.max) ? .max : UInt64(nanoseconds)
            )
        )
    }
}
