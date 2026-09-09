//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals
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

        /// Stable across launches (same bundle, same string every time) -- required for the
        /// system to reconnect this session to tasks that outlived a previous process. Not
        /// `private` -- `handleEvents(forIdentifier:completionHandler:)`'s identifier-matching
        /// guard is unit-tested directly against this exact value, rather than duplicating it.
        static let identifier = "\(Bundle.main.bundleIdentifier ?? "RequestDL").BackgroundDownloadTask"

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

        func schedule(
            request: URLRequest,
            id: String,
            destination: URL,
            serverTrust: Internals.ServerTrustPolicy.Descriptor? = nil,
            clientIdentity: Internals.ClientIdentityDescriptor? = nil
        ) {
            let task = urlSession().downloadTask(with: request)
            task.taskDescription = Self.encode(
                id: id,
                destination: destination,
                serverTrust: serverTrust,
                clientIdentity: clientIdentity
            )
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

        /// Cancels the download with this `id`, if one is currently running.
        ///
        /// No index of `id` -> `URLSessionTask` is kept around -- there is nowhere safe to keep
        /// one that would still be valid after a relaunch anyway, since a fresh process starts
        /// with nothing in memory. `allTasks` is the system's own live answer instead, always
        /// asked fresh: cheap enough for something that only runs when a caller explicitly asks
        /// to cancel something, not on any hot path.
        ///
        /// Cancelling a `URLSessionTask` this way makes it fail with `NSURLErrorCancelled`
        /// shortly after, through the ordinary `didCompleteWithError` callback below -- so a
        /// cancellation is reported through ``BackgroundDownloads/onEvent`` as an ordinary
        /// `.failed` event, not a distinct case of its own.
        ///
        /// - Returns: `true` if a matching, still-running download was found and cancelled;
        /// `false` if none was (already finished, never existed, or no download has ever been
        /// scheduled in this process at all -- checked without creating a session just to find
        /// out, since there would be nothing in it to cancel either way).
        @discardableResult
        func cancel(id: String) async -> Bool {
            guard let urlSession = lock.withLock({ _urlSession }) else {
                return false
            }

            guard let match = Self.firstTask(matching: id, in: await urlSession.allTasks) else {
                return false
            }

            match.cancel()
            return true
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

        // MARK: - URLSessionTaskDelegate

        /// Not part of `URLSessionDownloadDelegate` itself -- `URLSessionTaskDelegate`, which
        /// `URLSessionDownloadDelegate` already inherits from, so no extra protocol conformance
        /// is needed to implement it. A task with no persisted `serverTrust` (the common case:
        /// plain HTTPS, system trust) defers to the system's own default handling, exactly the
        /// behavior this method not existing at all already had before this existed.
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
                handleClientCertificateChallenge(task: task, completionHandler: completionHandler)
                return
            }

            guard let descriptor = Self.decodeServerTrust(task.taskDescription) else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            Internals.ServerTrustPolicy(descriptor: descriptor)
                .handle(challenge: challenge, completionHandler: completionHandler)
        }

        /// Rebuilds the identity fresh from disk for this one challenge and removes it again
        /// right after handing the credential over -- no identity is cached across calls, so
        /// there's nothing to invalidate if the same task is challenged again later (a redirect
        /// to a new host, for instance): it's simply rebuilt again, from the same file, the same
        /// way. Safe to remove immediately: once `SecItemCopyMatching` has handed back a
        /// `SecIdentity`, the in-memory object doesn't stop working just because the Keychain
        /// entry backing it is deleted afterward, the same assumption
        /// `Internals.URLSessionIdentityPolicy.deinit` already relies on, just at a smaller grain
        /// here.
        private func handleClientCertificateChallenge(
            task: URLSessionTask,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard let descriptor = Self.decodeClientIdentity(task.taskDescription) else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            guard let (handle, intermediates) = try? descriptor.makeIdentity() else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            completionHandler(
                .useCredential,
                URLCredential(
                    identity: handle.identity,
                    certificates: intermediates.isEmpty ? nil : intermediates,
                    persistence: .forSession
                )
            )

            Internals.RawBytesIdentityBuilder.remove(handle)
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
            let serverTrust: Internals.ServerTrustPolicy.Descriptor?
            let clientIdentity: Internals.ClientIdentityDescriptor?
        }

        // Not `private` -- unit-tested directly (`@testable import`) independent of any real
        // `URLSessionTask`, the same way `InternalsURLSessionUploadFileTests` covers its bridge
        // without a network round trip.
        static func encode(
            id: String,
            destination: URL,
            serverTrust: Internals.ServerTrustPolicy.Descriptor? = nil,
            clientIdentity: Internals.ClientIdentityDescriptor? = nil
        ) -> String? {
            guard
                let data = try? JSONEncoder().encode(
                    Descriptor(
                        id: id,
                        destination: destination,
                        serverTrust: serverTrust,
                        clientIdentity: clientIdentity
                    )
                )
            else {
                return nil
            }

            return String(data: data, encoding: .utf8)
        }

        static func decode(_ taskDescription: String?) -> (id: String, destination: URL)? {
            guard let descriptor = Self.decodeDescriptor(taskDescription) else {
                return nil
            }

            return (descriptor.id, descriptor.destination)
        }

        /// `nil` both when `taskDescription` isn't one this type encoded at all, and when it is
        /// but carries no `serverTrust` (the common, plain-HTTPS case) -- either way, the caller's
        /// only correct response is the same: defer to the system's default handling.
        static func decodeServerTrust(_ taskDescription: String?) -> Internals.ServerTrustPolicy.Descriptor? {
            Self.decodeDescriptor(taskDescription)?.serverTrust
        }

        /// `nil` both when `taskDescription` isn't one this type encoded at all, and when it is
        /// but carries no `clientIdentity` (no mTLS configured) -- either way, the caller's only
        /// correct response is the same: defer to the system's default handling.
        static func decodeClientIdentity(_ taskDescription: String?) -> Internals.ClientIdentityDescriptor? {
            Self.decodeDescriptor(taskDescription)?.clientIdentity
        }

        private static func decodeDescriptor(_ taskDescription: String?) -> Descriptor? {
            guard
                let taskDescription,
                let data = taskDescription.data(using: .utf8),
                let descriptor = try? JSONDecoder().decode(Descriptor.self, from: data)
            else {
                return nil
            }

            return descriptor
        }

        // MARK: - Task matching

        /// The pure part of ``cancel(id:)`` -- picking the right task out of a list -- pulled out
        /// on its own specifically so it's testable without a real background `URLSession` to ask
        /// `allTasks` of. A task with no `taskDescription`, or one this type didn't encode, simply
        /// never matches, the same way `decode(_:)`'s callers already treat it elsewhere.
        static func firstTask(matching id: String, in tasks: [URLSessionTask]) -> URLSessionTask? {
            tasks.first { decode($0.taskDescription)?.id == id }
        }
    }
}

#endif
