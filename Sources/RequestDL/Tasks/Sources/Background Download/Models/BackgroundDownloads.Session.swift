//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Dispatch
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
    /// One fixed identifier for the whole process, not one per download: a background session
    /// happily runs many concurrent tasks, and splitting them across sessions would only add
    /// surface to keep in sync on reconnection for no real benefit. Individual downloads are told
    /// apart by `URLSessionTask.taskDescription`, not by which session they run on.
    ///
    /// Not an `actor`: `urlSession(_:downloadTask:didFinishDownloadingTo:)` has to move the
    /// downloaded file synchronously, before returning, since the system deletes the temporary
    /// file right after that call returns; an `await` hop there would race the cleanup.
    final class Session: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

        // MARK: - Internal static properties

        static let shared = Session()

        /// Stable across launches (same bundle, same string every time): required for the
        /// system to reconnect this session to tasks that outlived a previous process.
        ///
        /// Not `private`: `handleEvents(forIdentifier:completionHandler:)`'s identifier-matching
        /// guard is unit-tested directly against this exact value, rather than duplicating it.
        static let identifier = "\(Bundle.main.bundleIdentifier ?? "RequestDL").BackgroundDownloadTask"

        // MARK: - Private types

        /// A `ClientIdentityDescriptor`'s already-built identity, kept for the rest of this
        /// process's lifetime once challenged once, so a redirect chain (or several downloads
        /// sharing one client certificate) doesn't re-read the two files and re-parse the key on
        /// every challenge, which `ClientIdentityDescriptor.makeIdentity()` otherwise does. Nothing
        /// is stored in a Keychain either way: this only saves that work.
        private struct CachedIdentity {
            let descriptor: Internals.ClientIdentityDescriptor
            let handle: Internals.IdentityHandle
            let intermediates: [SecCertificate]
        }

        /// A ceiling, not a working limit: a real app is expected to configure one, or a small
        /// handful of, distinct client identities across every background download it ever
        /// schedules, so this is never expected to fill up. It exists only so a pathological
        /// workload minting many distinct one-off identities can't grow this without bound for
        /// the rest of the process's lifetime.
        private static let maximumCachedIdentities = 4

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _urlSession: URLSession?
        private var _pendingCompletionHandler: (@Sendable () -> Void)?
        private var _onEvent: (@Sendable (BackgroundDownloads.Event) -> Void)?
        private var _cachedIdentities: [CachedIdentity] = []

        /// Decompressors the app registered (``BackgroundDownloads/registerDecompressors(_:)``),
        /// by lowercased `Content-Encoding`. They are what decodes a download that finished in a
        /// later launch than the one that scheduled it, where the algorithms of the original
        /// `content` no longer exist.
        private var _registeredDecompressors: [String: any Internals.DecompressionAlgorithm] = [:]

        /// What each download scheduled by *this* process configured, by the identifier of its
        /// `URLSessionTask`. Dropped as soon as that task ends, and empty after a relaunch.
        ///
        /// Not by `id`: a download that is cancelled for its resume data and scheduled again under
        /// the same `id` is a new task, and the old one's completion, which arrives after, must not
        /// take the new one's algorithms away.
        private var _scheduledDecompressors: [Int: [any Internals.DecompressionAlgorithm]] = [:]

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
            clientIdentity: Internals.ClientIdentityDescriptor? = nil,
            decompression: [any Internals.DecompressionAlgorithm]? = nil
        ) {
            let task = urlSession().downloadTask(with: request)
            keepDecompressors(decompression, for: task)
            task.taskDescription = Self.encode(
                id: id,
                destination: destination,
                serverTrust: serverTrust,
                clientIdentity: clientIdentity,
                // The single host this download was actually configured for. A background session
                // follows redirects on its own, and the challenge callback below has no other way
                // to tell the originally-requested host apart from one a redirect pointed it at.
                clientIdentityHost: clientIdentity == nil ? nil : request.url?.host,
                acceptedEncodings: decompression?.map { $0.contentEncodingValue.lowercased() }
            )
            task.resume()
        }

        /// Continues a download that stopped early, from the resume data `URLSession` produced for
        /// it. What is asked for comes from there, and not from a request: `host` is only the one
        /// a client identity is bound to, as in `schedule(request:...)`.
        func schedule(
            resumeData: BackgroundDownloadResumeData,
            id: String,
            destination: URL,
            serverTrust: Internals.ServerTrustPolicy.Descriptor? = nil,
            clientIdentity: Internals.ClientIdentityDescriptor? = nil,
            host: String? = nil,
            decompression: [any Internals.DecompressionAlgorithm]? = nil
        ) {
            let task = Self.makeTask(in: urlSession(), resumingFrom: resumeData, description: nil)

            // What was asked for is what the request that stopped asked for, which is in the resume
            // data and not in `content`. See `decompression(_:resumedFrom:)`.
            let decompression = Self.decompression(decompression, resumedFrom: task.originalRequest)
            keepDecompressors(decompression, for: task)
            task.taskDescription = Self.encode(
                id: id,
                destination: destination,
                serverTrust: serverTrust,
                clientIdentity: clientIdentity,
                clientIdentityHost: clientIdentity == nil ? nil : host,
                acceptedEncodings: decompression?.map { $0.contentEncodingValue.lowercased() }
            )

            task.resume()
        }

        func register(_ algorithm: any Internals.DecompressionAlgorithm) {
            lock.withLock { _registeredDecompressors[algorithm.contentEncodingValue.lowercased()] = algorithm }
        }

        /// The algorithm that decodes `encoding` (lowercased) for `task`: the one it was scheduled
        /// with in this process, else one the app registered.
        func decompressor(
            forEncoding encoding: String,
            task: URLSessionTask
        ) -> (any Internals.DecompressionAlgorithm)? {
            lock.withLock {
                _scheduledDecompressors[task.taskIdentifier]?.first { $0.contentEncodingValue.lowercased() == encoding }
                    ?? _registeredDecompressors[encoding]
            }
        }

        func forgetDecompressors(for task: URLSessionTask) {
            lock.withLock { _scheduledDecompressors[task.taskIdentifier] = nil }
        }

        func keepDecompressors(_ algorithms: [any Internals.DecompressionAlgorithm]?, for task: URLSessionTask) {
            lock.withLock { _scheduledDecompressors[task.taskIdentifier] = algorithms }
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
            // identifier is what makes the system replay queued delegate callbacks; there is no
            // separate "reconnect" call.
            _ = urlSession()
        }

        /// Cancels the download with this `id`, if one is currently running.
        ///
        /// No index of `id` -> `URLSessionTask` is kept around: there is nowhere safe to keep
        /// one that would still be valid after a relaunch anyway, since a fresh process starts
        /// with nothing in memory. `allTasks` is the system's own live answer instead, always
        /// asked fresh: cheap enough for something that only runs when a caller explicitly asks
        /// to cancel something, not on any hot path.
        ///
        /// Asked of the session even when nothing was scheduled in this process: after a manual
        /// relaunch the system may still be running downloads from the previous one, and only
        /// creating the session with the stable identifier reattaches them.
        ///
        /// Cancelling a `URLSessionTask` this way makes it fail with `NSURLErrorCancelled`
        /// shortly after, through the ordinary `didCompleteWithError` callback below, so a
        /// cancellation is reported through ``BackgroundDownloads/onEvent`` as an ordinary
        /// `.failed` event, not a distinct case of its own.
        ///
        /// - Returns: `true` if a matching, still-running download was found and cancelled;
        /// `false` if none was (already finished or never existed).
        @discardableResult
        func cancel(id: String) async -> Bool {
            guard let match = Self.firstTask(matching: id, in: await urlSession().allTasks) else {
                return false
            }

            match.cancel()
            return true
        }

        /// What ``control(id:_:)`` does to a download.
        enum Control {
            case suspend
            case resume
        }

        /// Pauses or lets go on the download with this `id`, found the same way ``cancel(id:)``
        /// finds one, with nothing kept about it.
        ///
        /// - Returns: `true` if a matching download was found, `false` if none was.
        func control(id: String, _ action: Control) async -> Bool {
            guard let match = Self.firstTask(matching: id, in: await urlSession().allTasks) else {
                return false
            }

            Self.apply(action, to: match)
            return true
        }

        /// Cancels the download with this `id` and hands back what `URLSession` kept to continue
        /// it. `nil` when there was no such download, or nothing to continue from.
        func cancelProducingResumeData(id: String) async -> BackgroundDownloadResumeData? {
            guard
                let match = Self.firstTask(matching: id, in: await urlSession().allTasks),
                let download = match as? URLSessionDownloadTask
            else {
                return nil
            }

            return await Self.cancelProducingResumeData(of: download)
        }

        // MARK: - Static methods

        static func apply(_ action: Control, to task: URLSessionTask) {
            switch action {
            case .suspend:
                task.suspend()
            case .resume:
                task.resume()
            }
        }

        static func cancelProducingResumeData(of task: URLSessionDownloadTask) async -> BackgroundDownloadResumeData? {
            await withCheckedContinuation { continuation in
                task.cancel(byProducingResumeData: { data in
                    continuation.resume(returning: data.map(BackgroundDownloadResumeData.init(data:)))
                })
            }
        }

        /// What a failed download's error carries to continue it from where it got to, where
        /// `URLSession` puts it: as the error's own property when it is a `URLError`, and in its
        /// `userInfo` otherwise.
        static func resumeData(from error: any Error) -> BackgroundDownloadResumeData? {
            let data =
                (error as? URLError)?.downloadTaskResumeData
                ?? (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data

            return data.map(BackgroundDownloadResumeData.init(data:))
        }

        /// The task that continues a download from `resumeData`, ready to be resumed, with
        /// `description` as what tells every callback about it which download it is.
        static func makeTask(
            in session: URLSession,
            resumingFrom resumeData: BackgroundDownloadResumeData,
            description: String?
        ) -> URLSessionDownloadTask {
            let task = session.downloadTask(withResumeData: resumeData.data)
            task.taskDescription = description
            return task
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

        /// Not part of `URLSessionDownloadDelegate` itself: it's `URLSessionTaskDelegate`, which
        /// `URLSessionDownloadDelegate` already inherits from, so no extra protocol conformance
        /// is needed to implement it.
        ///
        /// A task with no persisted `serverTrust` (the common case: plain HTTPS, system trust)
        /// defers to the system's own default handling, exactly the behavior this method not
        /// existing at all already had before this existed.
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
                handleClientCertificateChallenge(
                    task: task,
                    challengedHost: challenge.protectionSpace.host,
                    completionHandler: completionHandler
                )
                return
            }

            // Every task on this session was scheduled by this type, so one whose description does
            // not decode (a format from another version, or none at all) is one whose pins are
            // unknown, not one that has none. It could not report anything either, since its
            // events and its file are tied to that same description. Answering with the system's
            // default handling would silently drop the pins, so the server-trust challenge is
            // refused instead.
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                Self.decode(task.taskDescription) == nil
            {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            guard let descriptor = Self.decodeServerTrust(task.taskDescription) else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            Internals.ServerTrustPolicy(descriptor: descriptor)
                .handle(challenge: challenge, completionHandler: completionHandler)
        }

        /// Reuses this exact descriptor's already-built identity when this same task (or another
        /// one sharing the same client certificate) was challenged before in this process,
        /// rebuilding from disk only on the first challenge for a given descriptor. See
        /// `CachedIdentity`'s own doc comment for why that's worth doing.
        ///
        /// Gated on `challengedHost`, which is how a challenge from a redirect target is turned
        /// away. See `decodeClientIdentity(_:challengedBy:)` for why.
        ///
        /// The cached `handle` outliving any single challenge is safe: the identity is built in
        /// memory and holds its own key, so it depends on nothing outside this process.
        private func handleClientCertificateChallenge(
            task: URLSessionTask,
            challengedHost: String,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard
                let descriptor = Self.decodeClientIdentity(
                    task.taskDescription,
                    challengedBy: challengedHost
                )
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            guard let (handle, intermediates) = resolvedIdentity(for: descriptor) else {
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
        }

        /// The identity for `descriptor`, from `_cachedIdentities` if this exact descriptor was
        /// already resolved before in this process, or freshly built (and then cached) otherwise.
        ///
        /// `descriptor.makeIdentity()` (two small file reads and a key parse) runs while `lock` is
        /// held, like every other access to this instance's state. Serializing it against a
        /// concurrently-arriving challenge for a different descriptor is an acceptable cost.
        ///
        /// Not `private`, so unit tests (`@testable import`) can confirm a repeat resolution reuses
        /// the exact same `Internals.IdentityHandle` instance without needing a real, entitled
        /// background session or a genuine `URLAuthenticationChallenge` round trip.
        func resolvedIdentity(
            for descriptor: Internals.ClientIdentityDescriptor
        ) -> (handle: Internals.IdentityHandle, intermediates: [SecCertificate])? {
            lock.withLock {
                if let cached = _cachedIdentities.first(where: { $0.descriptor == descriptor }) {
                    return (cached.handle, cached.intermediates)
                }

                guard let (handle, intermediates) = try? descriptor.makeIdentity() else {
                    return nil
                }

                if _cachedIdentities.count >= Self.maximumCachedIdentities {
                    _cachedIdentities.removeFirst()
                }
                _cachedIdentities.append(
                    CachedIdentity(descriptor: descriptor, handle: handle, intermediates: intermediates)
                )

                return (handle, intermediates)
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

            defer { forgetDecompressors(for: downloadTask) }

            // URLSession calls this for *any* HTTP status, so without this an error page would
            // replace the file already at `destination` and be reported as `.completed`. Checked
            // before touching `destination` at all; URLSession removes `location` itself once
            // this returns.
            if let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode,
                !(200..<300).contains(statusCode)
            {
                onEvent?(
                    .failed(
                        id: id,
                        destination: destination,
                        error: BackgroundDownloadStatusCodeError(statusCode: statusCode)
                    )
                )
                return
            }

            do {
                // `replaceItemAt`, not a `removeItem` + `moveItem` pair: those are two separate
                // steps, so a `moveItem` failure after the `removeItem` already succeeded (full
                // disk, a permissions change, ...) would leave `destination` empty, permanently
                // losing whatever was already downloaded there before this attempt even though
                // the failure was transient. `replaceItemAt` swaps the two atomically, leaving
                // the original file untouched if the replacement can't complete.
                //
                // The directory is created first: `URLSession` deletes `location` as soon as this
                // returns, so a destination folder that is gone by now (a subfolder of `Caches`
                // the system cleared while the app was not running, say) would otherwise lose a
                // download that may have taken hours.
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                // Decoded here, in the callback, and not afterwards: this is the only time the
                // downloaded file exists, and a download that finished in a relaunch only has the
                // time until `urlSessionDidFinishEvents` lets the app go back to sleep.
                let decoded = try decodedFile(
                    from: location,
                    response: downloadTask.response,
                    task: downloadTask,
                    destination: destination
                )
                let source = decoded ?? location

                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
                    } else {
                        try FileManager.default.moveItem(at: source, to: destination)
                    }
                } catch {
                    if let decoded {
                        try? FileManager.default.removeItem(at: decoded)
                    }
                    throw error
                }

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

        /// Also fires with `error == nil` on success; ignored here, since a successful download
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

            forgetDecompressors(for: task)
            onEvent?(.failed(id: id, destination: destination, error: error))
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            let handler = lock.withLock {
                defer { _pendingCompletionHandler = nil }
                return _pendingCompletionHandler
            }

            // On the main queue, as the system's own sample code does with the handler it passes to
            // `application(_:handleEventsForBackgroundURLSession:completionHandler:)`. This is
            // called on the delegate queue, a background one.
            if let handler {
                DispatchQueue.main.async { handler() }
            }
        }

        // MARK: - taskDescription encoding

        /// Everything a delegate callback needs to know about one download, carried on the
        /// `URLSessionTask` itself (`taskDescription`) rather than in a store RequestDL would
        /// otherwise have to keep in sync with the system's own task bookkeeping: the system
        /// already persists this string across a relaunch for free.
        private struct Descriptor: Codable {
            let id: String
            let destination: URL
            let serverTrust: Internals.ServerTrustPolicy.Descriptor?
            let clientIdentity: Internals.ClientIdentityDescriptor?

            /// Optional so a `taskDescription` persisted by an older version of this package still
            /// decodes after an app upgrade. `nil` never matches a challenge's host, so such a
            /// task falls back to default handling rather than presenting the identity blind,
            /// which is the right way for this particular field to fail.
            let clientIdentityHost: String?

            /// The `Content-Encoding` values the request asked for, when `Accept-Encoding` was
            /// taken over (which switches CFNetwork's own decoding off), else `nil`. Optional for
            /// the same reason as `clientIdentityHost`, and `nil` also means what an older
            /// version did: the downloaded bytes are moved as they came.
            let acceptedEncodings: [String]?
        }

        // Not `private`: unit-tested directly (`@testable import`) independent of any real
        // `URLSessionTask`, the same way `InternalsURLSessionUploadFileTests` covers its bridge
        // without a network round trip.
        static func encode(
            id: String,
            destination: URL,
            serverTrust: Internals.ServerTrustPolicy.Descriptor? = nil,
            clientIdentity: Internals.ClientIdentityDescriptor? = nil,
            clientIdentityHost: String? = nil,
            acceptedEncodings: [String]? = nil
        ) -> String? {
            guard
                let data = try? JSONEncoder().encode(
                    Descriptor(
                        id: id,
                        destination: destination,
                        serverTrust: serverTrust,
                        clientIdentity: clientIdentity,
                        clientIdentityHost: clientIdentityHost,
                        acceptedEncodings: acceptedEncodings
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
        /// but carries no `serverTrust` (the common, plain-HTTPS case). Either way, the caller's
        /// only correct response is the same: defer to the system's default handling.
        static func decodeServerTrust(_ taskDescription: String?) -> Internals.ServerTrustPolicy.Descriptor? {
            Self.decodeDescriptor(taskDescription)?.serverTrust
        }

        /// The persisted client identity, but only when `challengedHost` is the host this download
        /// was originally scheduled against.
        ///
        /// A background session follows redirects by itself, and a client certificate identifies
        /// *us* to whoever receives it. Answering a redirect target's challenge with it would hand
        /// the caller's identity to whoever controls that redirect, so the identity is bound to one
        /// host at schedule time and checked here. This is the same gate
        /// `Internals.URLSessionIdentityPolicy` applies on the foreground executor, for the same
        /// reason.
        ///
        /// Server-trust handling deliberately stays host-independent (see that type's own doc
        /// comment): pinning has to survive a redirect, whereas an identity must not.
        ///
        /// `nil` therefore covers four cases that all deserve the same response (defer to the
        /// system's default handling): a `taskDescription` this type didn't encode, one carrying no
        /// `clientIdentity` (no mTLS configured, the common case), one persisted before this
        /// package recorded a host at all, and one whose host isn't the one now asking.
        static func decodeClientIdentity(
            _ taskDescription: String?,
            challengedBy challengedHost: String
        ) -> Internals.ClientIdentityDescriptor? {
            guard
                let descriptor = Self.decodeDescriptor(taskDescription),
                descriptor.clientIdentityHost == challengedHost
            else {
                return nil
            }

            return descriptor.clientIdentity
        }

        static func decodeAcceptedEncodings(_ taskDescription: String?) -> [String]? {
            Self.decodeDescriptor(taskDescription)?.acceptedEncodings
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

        /// The pure part of ``cancel(id:)`` (picking the right task out of a list), pulled out
        /// on its own specifically so it's testable without a real background `URLSession` to ask
        /// `allTasks` of. A task with no `taskDescription`, or one this type didn't encode, simply
        /// never matches, the same way `decode(_:)`'s callers already treat it elsewhere.
        static func firstTask(matching id: String, in tasks: [URLSessionTask]) -> URLSessionTask? {
            tasks.first { decode($0.taskDescription)?.id == id }
        }
    }
}

#endif
