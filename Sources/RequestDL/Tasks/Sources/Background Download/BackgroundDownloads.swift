//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Observes and integrates with every ``BackgroundDownloadTask`` in the process.
///
/// Deliberately not a member of ``BackgroundDownloadTask`` itself: a generic type's static
/// storage is per-specialization in Swift, and every `BackgroundDownloadTask<Content>` call site
/// has its own concrete `Content` -- a handler stored there would only ever see the downloads
/// created with that exact `Content` type, not every download in the app. `BackgroundDownloads`
/// is a plain, non-generic namespace specifically so there is exactly one of everything below,
/// regardless of how many different `BackgroundDownloadTask<Content>` specializations exist.
public enum BackgroundDownloads {

    /// One thing that happened to a ``BackgroundDownloadTask``, identified by the `id` it was
    /// created with.
    public enum Event: Sendable {
        /// `bytesWritten`/`totalBytesExpected` are the running totals for the whole download, not
        /// the size of this particular callback -- matching
        /// `URLSessionDownloadDelegate.urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)`.
        case progress(id: String, destination: URL, bytesWritten: Int64, totalBytesExpected: Int64)

        /// The file is already at `destination` by the time this fires -- moved there from
        /// `URLSession`'s own temporary location before this event is ever produced.
        case completed(id: String, destination: URL)

        case failed(id: String, destination: URL, error: any Error)
    }

    /// Called for every event from every ``BackgroundDownloadTask`` in the process, on an
    /// unspecified queue.
    ///
    /// Set this once, early -- ideally before any ``BackgroundDownloadTask`` is ever created,
    /// and unconditionally on every launch, including a launch the system triggered only to
    /// deliver background events (there is no user-visible UI at that point, but the events still
    /// need somewhere to go).
    public static var onEvent: (@Sendable (Event) -> Void)? {
        get { Session.shared.onEvent }
        set { Session.shared.onEvent = newValue }
    }

    /// Forwards `application(_:handleEventsForBackgroundURLSession:completionHandler:)` from the
    /// app's own `UIApplicationDelegate`.
    ///
    /// Required for background downloads to work at all: this is how the system hands back the
    /// identifier of the session it wants reconnected, and the completion handler that has to be
    /// called once every queued event has actually been delivered to ``onEvent`` -- calling it
    /// any earlier risks the system snapshotting the app before its state reflects what actually
    /// finished.
    ///
    /// ```swift
    /// func application(
    ///     _ application: UIApplication,
    ///     handleEventsForBackgroundURLSession identifier: String,
    ///     completionHandler: @escaping () -> Void
    /// ) {
    ///     BackgroundDownloads.handleEvents(
    ///         forBackgroundURLSession: identifier,
    ///         completionHandler: completionHandler
    ///     )
    /// }
    /// ```
    public static func handleEvents(
        forBackgroundURLSession identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        Session.shared.handleEvents(forIdentifier: identifier, completionHandler: completionHandler)
    }
}

#endif
