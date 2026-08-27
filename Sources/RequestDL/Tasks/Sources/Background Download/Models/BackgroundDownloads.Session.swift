//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension BackgroundDownloads {

    /// The single `URLSession` backing every ``BackgroundDownloadTask``, plus the delegate
    /// callbacks that turn its events into ``BackgroundDownloads/Event``.
    ///
    /// One fixed identifier for the whole process, not one per download -- a background session
    /// happily runs many concurrent tasks, and splitting them across sessions would only add
    /// surface to keep in sync on reconnection for no real benefit. Individual downloads are told
    /// apart by `URLSessionTask.taskDescription`, not by which session they run on.
    ///
    /// Not an `actor`: `urlSession(_:downloadTask:didFinishDownloadingTo:)` has to move the
    /// downloaded file synchronously, before returning, since the system deletes the temporary
    /// file right after that call returns -- an `await` hop there would race the cleanup.
    final class Session: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

        // MARK: - Internal static properties

        static let shared = Session()

        // MARK: - Private static properties

        /// Stable across launches (same bundle, same string every time) -- required for the
        /// system to reconnect this session to tasks that outlived a previous process.
        private static let identifier = "\(Bundle.main.bundleIdentifier ?? "RequestDL").BackgroundDownloadTask"

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _urlSession: URLSession?
        private var _pendingCompletionHandler: (@Sendable () -> Void)?
        private var _onEvent: (@Sendable (BackgroundDownloads.Event) -> Void)?

        // MARK: - Internal properties

        var onEvent: (@Sendable (BackgroundDownloads.Event) -> Void)? {
            get { lock.withLock { _onEvent } }
            set { lock.withLock { _onEvent = newValue } }
        }

        // MARK: - Internal methods

        func schedule(request: URLRequest, id: String, destination: URL) {
            let task = urlSession().downloadTask(with: request)
            task.taskDescription = Self.encode(id: id, destination: destination)
            task.resume()
        }

        /// Forwarded from `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
        /// Ignores any identifier other than this type's own, in case the app also manages its
        /// own, unrelated background sessions.
        func handleEvents(
            forIdentifier identifier: String,
            completionHandler: @escaping @Sendable () -> Void
        ) {
            guard identifier == Self.identifier else {
                return
            }

            lock.withLock { _pendingCompletionHandler = completionHandler }

            // Recreating the session (or confirming it already exists) with the matching
            // identifier is what makes the system replay queued delegate callbacks -- there is no
            // separate "reconnect" call.
            _ = urlSession()
        }

        // MARK: - Private methods

        private func urlSession() -> URLSession {
            lock.withLock {
                if let _urlSession {
                    return _urlSession
                }

                let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
                let urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                _urlSession = urlSession
                return urlSession
            }
        }

        // MARK: - URLSessionDownloadDelegate

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            guard let (id, destination) = Self.decode(downloadTask.taskDescription) else {
                return
            }

            do {
                // Best-effort -- a destination that doesn't already exist is the common case, and
                // `moveItem` below is what actually needs to succeed.
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                onEvent?(.completed(id: id, destination: destination))
            } catch {
                onEvent?(.failed(id: id, destination: destination, error: error))
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard let (id, destination) = Self.decode(downloadTask.taskDescription) else {
                return
            }

            onEvent?(
                .progress(
                    id: id,
                    destination: destination,
                    bytesWritten: totalBytesWritten,
                    totalBytesExpected: totalBytesExpectedToWrite
                )
            )
        }

        /// Also fires with `error == nil` on success -- ignored here, since a successful download
        /// is already reported from `didFinishDownloadingTo` above, once the file has actually
        /// been moved to `destination`.
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: (any Error)?
        ) {
            guard let error, let (id, destination) = Self.decode(task.taskDescription) else {
                return
            }

            onEvent?(.failed(id: id, destination: destination, error: error))
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            let handler = lock.withLock {
                defer { _pendingCompletionHandler = nil }
                return _pendingCompletionHandler
            }

            handler?()
        }

        // MARK: - taskDescription encoding

        /// Everything a delegate callback needs to know about one download, carried on the
        /// `URLSessionTask` itself (`taskDescription`) rather than in a store RequestDL would
        /// otherwise have to keep in sync with the system's own task bookkeeping -- the system
        /// already persists this string across a relaunch for free.
        private struct Descriptor: Codable {
            let id: String
            let destination: URL
        }

        // Not `private` -- unit-tested directly (`@testable import`) independent of any real
        // `URLSessionTask`, the same way `InternalsURLSessionUploadFileTests` covers its bridge
        // without a network round trip.
        static func encode(id: String, destination: URL) -> String? {
            guard let data = try? JSONEncoder().encode(Descriptor(id: id, destination: destination)) else {
                return nil
            }

            return String(data: data, encoding: .utf8)
        }

        static func decode(_ taskDescription: String?) -> (id: String, destination: URL)? {
            guard
                let taskDescription,
                let data = taskDescription.data(using: .utf8),
                let descriptor = try? JSONDecoder().decode(Descriptor.self, from: data)
            else {
                return nil
            }

            return (descriptor.id, descriptor.destination)
        }
    }
}

#endif
