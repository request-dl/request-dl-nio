//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.CocoaError
import struct Foundation.URL
#endif

/// Schedules a download that keeps running even if the app is suspended or terminated, via
/// `URLSession`'s background transfer support.
///
/// Unlike ``DownloadTask``, ``result()`` does not wait for the download to finish. It can't:
/// the transfer may complete long after this call returns, in a different process launch
/// entirely.
///
/// Register ``BackgroundDownloads/onEvent`` to be told when it actually completes,
/// fails, or makes progress, and forward
/// `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to
/// ``BackgroundDownloads/handleEvents(forBackgroundURLSession:completionHandler:)`` for the
/// system to be able to reconnect to it after a relaunch.
///
/// ```swift
/// try await BackgroundDownloadTask(
///     id: "episode-42",
///     destination: episodesDirectory.appendingPathComponent("episode-42.mp3")
/// ) {
///     BaseURL("api.example.com")
///     Path("episodes/42/audio")
/// }
/// .result()
/// ```
///
/// `content` can configure ``TrustRoots``/``AdditionalTrustRoots``/``SecureConnection/verification(_:)``
/// freely: none of them need a Keychain round-trip to survive a relaunch, only the certificate
/// bytes themselves, which travel alongside `id`/`destination` in the scheduled task's own state.
///
/// ## Redirects
///
/// The system runs a background download and follows its redirects on its own, without asking the
/// app, which is how `URLSession` behaves for any background transfer. So the redirect handling
/// the other tasks apply does not exist here:
///
/// - Headers are not removed when a redirect leaves the host. `Authorization` is the exception,
///   because the system removes it on every redirect, to the same host as well. A `Cookie`, a
///   `Proxy-Authorization` or an API-key header set on the request is sent to whichever host the
///   redirect names, so only point a background download at a server you trust not to redirect
///   somewhere else, or authenticate with `Authorization` or a signed URL.
/// - ``Session/disableRedirect()``, ``Session/enableRedirectFollow(max:allowCycles:)`` and
///   ``Session/redirectStrategy(_:)`` have no effect.
///
/// ## Request body
///
/// The request body is not sent. A background download is handed to the system as a download
/// task, which has no body to send, so whatever `content` declares as one (``Payload`` and the
/// like) is dropped without an error or a warning. The rest of the request is built as usual,
/// and that includes what a ``Payload`` sets on it besides the body: the method becomes `POST`
/// when none was declared, and its `Content-Type` is sent. A request that needs a body, such as
/// a `POST` that answers with the file, cannot be a background download: use ``DownloadTask``
/// for it, in the foreground.
///
/// ## Client certificates
///
/// A client certificate (mTLS) works too, as long as both ``Certificate`` and ``PrivateKey`` come
/// from a **file path**, not in-memory bytes. See ``BackgroundDownloadUnsupportedConfigurationError``
/// for the specific cases that still aren't supported.
///
/// What is saved with the download is the path of each file, never the key's bytes, and the
/// identity is rebuilt from those files every time the server asks for it, in a later launch
/// too. A path that stops pointing at the file makes that fail, and the download then goes on
/// without a client certificate, which a server that requires one refuses. Do not count on an
/// absolute path inside the app's own container staying valid: the system may change it when
/// the app is updated or restored, and the app bundle's path in particular is not stable. A
/// download that is still running across such a change is the one at risk, so schedule it again
/// afterwards if its certificate files are in the container.
public struct BackgroundDownloadTask<Content: Property> {

    // MARK: - Private properties

    private let id: String
    private let destination: URL
    private let content: Content
    private let resumeData: BackgroundDownloadResumeData?

    // MARK: - Inits

    /// - Parameters:
    ///   - id: Identifies this download in every ``BackgroundDownloads/Event`` it produces.
    ///     Not the `URLSession` background session identifier, which RequestDL manages
    ///     internally; this is only ever your own correlation key.
    ///   - destination: Where the downloaded file ends up. Overwrites anything already there
    ///     once the download completes.
    ///   - content: The request to make, exactly as with any other task.
    public init(
        id: String,
        destination: URL,
        @PropertyBuilder content: () -> Content
    ) {
        self.id = id
        self.destination = destination
        self.content = content()
        self.resumeData = nil
    }

    /// Continues a download that stopped early, from where it got to, instead of starting it over.
    ///
    /// `content` is the request of the download that stopped, written again: what is asked for
    /// comes from `resumeData`, and `content` is what the download needs besides that, which is
    /// its trust and client certificate configuration and the host the latter is bound to.
    /// Whether the server still has the same resource is checked as it continues, and a
    /// download whose resource changed fails again, with no resume data: start it over with
    /// ``init(id:destination:content:)``.
    ///
    /// - Parameters:
    ///   - id: Identifies this download in every ``BackgroundDownloads/Event`` it produces. The
    ///     one it had before is the natural choice.
    ///   - destination: Where the downloaded file ends up, as in ``init(id:destination:content:)``.
    ///   - resumeData: What `URLSession` produced for the download that stopped, from
    ///     ``BackgroundDownloads/resumeData(from:)`` or
    ///     ``BackgroundDownloads/cancelProducingResumeData(id:)``.
    ///   - content: The request of the download that stopped.
    public init(
        id: String,
        destination: URL,
        resumingFrom resumeData: BackgroundDownloadResumeData,
        @PropertyBuilder content: () -> Content
    ) {
        self.id = id
        self.destination = destination
        self.content = content()
        self.resumeData = resumeData
    }

    // MARK: - Public methods

    /// Resolves `content` and schedules the download (or continues it, for one made with
    /// ``init(id:destination:resumingFrom:content:)``). Returns as soon as it's scheduled;
    /// use ``BackgroundDownloads/onEvent`` to observe how it turns out.
    ///
    /// - Throws: `CocoaError.fileWriteUnsupportedScheme` if `destination` is not a file URL.
    ///   ``BackgroundDownloadUnsupportedConfigurationError`` if `content` configures a
    ///   client certificate or SPKI pin this executor can't rebuild after a relaunch (see its own
    ///   documentation for the specific cases), or any error `content` itself throws while being
    ///   resolved into a request (an invalid URL, a certificate file that can't be read, etc.),
    ///   the same errors any other task can throw at this stage.
    public func result() async throws {
        // The downloaded file is moved here from the delegate, possibly in a later launch, and
        // only a file URL says where. Refused now, since by then the download would be done and
        // the file already deleted by the system.
        guard destination.isFileURL else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }

        let resolved = try await Resolve(
            root: content,
            environment: RequestEnvironmentValues()
        ).build()

        let serverTrust: Internals.ServerTrustPolicy.Descriptor?
        do {
            serverTrust = try resolved.session.configuration.secureConnection.map {
                try Internals.ServerTrustPolicy.resolve(from: $0).descriptor()
            }
        } catch let error as Internals.ServerTrustPolicy.DescriptorError {
            throw BackgroundDownloadUnsupportedConfigurationError(error)
        }

        let clientIdentity: Internals.ClientIdentityDescriptor?
        do {
            clientIdentity = try resolved.session.configuration.secureConnection.flatMap {
                try Internals.ClientIdentityDescriptor.resolve(from: $0)
            }
        } catch let error as Internals.ClientIdentityDescriptor.ResolutionError {
            throw BackgroundDownloadUnsupportedConfigurationError(error)
        }

        let request = try resolved.requestConfiguration.buildURLRequestWithoutBody()

        if let resumeData {
            BackgroundDownloads.Session.shared.schedule(
                resumeData: resumeData,
                id: id,
                destination: destination,
                serverTrust: serverTrust,
                clientIdentity: clientIdentity,
                host: request.url?.host
            )
            return
        }

        BackgroundDownloads.Session.shared.schedule(
            request: request,
            id: id,
            destination: destination,
            serverTrust: serverTrust,
            clientIdentity: clientIdentity
        )
    }
}

#endif
