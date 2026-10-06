//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// What `URLSession` hands back about a download that stopped early, to continue it later from
/// where it got to instead of from the beginning.
///
/// Opaque: its contents are `URLSession`'s own, and their format is neither documented nor stable
/// across versions of the system, which is also why nothing here converts it to or from a
/// ``DownloadResumptionPoint``. It is `Codable`, to be kept somewhere across launches of the
/// application, and it is the caller who keeps it: RequestDL stores nothing.
///
/// Get one from a ``BackgroundDownloads/Event/failed(id:destination:error:)`` event with
/// ``BackgroundDownloads/resumeData(from:)``, or by cancelling with
/// ``BackgroundDownloads/cancelProducingResumeData(id:)``, and hand it back to
/// ``BackgroundDownloadTask/init(id:destination:resumingFrom:content:)``.
///
/// It can't always be used: whether the server still has the same resource is checked when the
/// download is continued, and a download whose resource changed fails again, with an error that
/// carries no resume data. Start it over from the beginning then.
public struct BackgroundDownloadResumeData: Sendable, Hashable, Codable {

    /// What `URLSession` produced, as it produced it.
    public let data: Data

    /// - Parameter data: What `URLSession` produced, as it produced it.
    public init(data: Data) {
        self.data = data
    }
}

#endif
