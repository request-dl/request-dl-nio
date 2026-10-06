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
/// has its own concrete `Content`, a handler stored there would only ever see the downloads
/// created with that exact `Content` type, not every download in the app. `BackgroundDownloads`
/// is a plain, non-generic namespace specifically so there is exactly one of everything below,
/// regardless of how many different `BackgroundDownloadTask<Content>` specializations exist.
public enum BackgroundDownloads {

    /// One thing that happened to a ``BackgroundDownloadTask``, identified by the `id` it was
    /// created with.
    public enum Event: Sendable {
        /// `bytesWritten`/`totalBytesExpected` are the running totals for the whole download, not
        /// the size of this particular callback, matching
        /// `URLSessionDownloadDelegate.urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)`.
        case progress(id: String, destination: URL, bytesWritten: Int64, totalBytesExpected: Int64)

        /// The file is already at `destination` by the time this fires, moved there from
        /// `URLSession`'s own temporary location before this event is ever produced.
        case completed(id: String, destination: URL)

        /// The download stopped without finishing. When it can be continued from where it got to
        /// (the server supports asking for a part, and some of the file had arrived), `error`
        /// carries what it takes: see ``BackgroundDownloads/resumeData(from:)``.
        case failed(id: String, destination: URL, error: any Error)
    }

    /// Called for every event from every ``BackgroundDownloadTask`` in the process, on an
    /// unspecified queue.
    ///
    /// Set this once, early, ideally before any ``BackgroundDownloadTask`` is ever created,
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
    /// called once every queued event has actually been delivered to ``onEvent``.
    ///
    /// Calling it any earlier risks the system snapshotting the app before its state reflects
    /// what actually finished.
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

    /// Cancels the ``BackgroundDownloadTask`` scheduled with this `id`, if it's still running.
    ///
    /// A cancelled download is reported through ``onEvent`` as an ordinary `.failed` event (the
    /// underlying error is `NSURLErrorCancelled`), the same way any other failure is: there is
    /// no separate "was cancelled" event of its own.
    ///
    /// - Returns: `true` if a matching, still-running download was found and cancelled; `false`
    ///   if none was, since it may have already finished, failed, or never existed.
    @discardableResult
    public static func cancel(id: String) async -> Bool {
        await Session.shared.cancel(id: id)
    }

    /// Pauses the ``BackgroundDownloadTask`` scheduled with this `id`: nothing more is downloaded
    /// until ``resume(id:)``. The connection may be given up by the system or the server while it
    /// waits, in which case it reconnects on resuming, from where it got to.
    ///
    /// Not an event: a pause is not reported through ``onEvent``, since it is something you asked
    /// for, and a download that is paused simply makes no more progress.
    ///
    /// - Returns: `true` if a matching, still-running download was found and paused; `false` if
    ///   none was, since it may have already finished, failed, or never existed.
    @discardableResult
    public static func suspend(id: String) async -> Bool {
        await Session.shared.control(id: id, .suspend)
    }

    /// Lets the ``BackgroundDownloadTask`` scheduled with this `id` carry on after
    /// ``suspend(id:)``.
    ///
    /// - Returns: `true` if a matching download was found and resumed; `false` if none was.
    @discardableResult
    public static func resume(id: String) async -> Bool {
        await Session.shared.control(id: id, .resume)
    }

    /// Cancels the ``BackgroundDownloadTask`` scheduled with this `id`, like ``cancel(id:)``, and
    /// hands back what it takes to continue it later from where it got to.
    ///
    /// The download is cancelled whether or not there is anything to hand back, and is reported
    /// through ``onEvent`` as a `.failed` event all the same.
    ///
    /// - Returns: The resume data, or `nil` if there was no matching, still-running download, or
    ///   if it can't be continued (the server gave no way to tell the resource is the same one,
    ///   or nothing of the file had arrived yet).
    public static func cancelProducingResumeData(id: String) async -> BackgroundDownloadResumeData? {
        await Session.shared.cancelProducingResumeData(id: id)
    }

    /// What it takes to continue a download that stopped early, from the error of its
    /// ``Event/failed(id:destination:error:)`` event.
    ///
    /// - Returns: `nil` when `error` carries none: a download that failed for a reason that
    ///   continuing can't fix, one that stopped before any of the file had arrived, or one from a
    ///   server that doesn't support asking for a part of a resource.
    public static func resumeData(from error: any Error) -> BackgroundDownloadResumeData? {
        Session.resumeData(from: error)
    }
}

#endif
