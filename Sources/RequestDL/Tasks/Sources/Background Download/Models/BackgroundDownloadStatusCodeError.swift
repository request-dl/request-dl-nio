//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

/// Reported through ``BackgroundDownloads/Event/failed(id:destination:error:)`` when a
/// ``BackgroundDownloadTask``'s server answers with a non-success (non-2xx) HTTP status.
///
/// `URLSession` hands a download task's body to its delegate as a finished file whatever the
/// status was, so an error page (a `404`'s HTML, a `401`'s JSON) would otherwise be moved to
/// `destination`, replacing whatever was already there, and reported as `.completed`. The
/// existing file at `destination` is left untouched instead.
public struct BackgroundDownloadStatusCodeError: Error, Sendable, Hashable {

    /// The HTTP status code the server answered with.
    public let statusCode: Int

    init(statusCode: Int) {
        self.statusCode = statusCode
    }
}

#endif
