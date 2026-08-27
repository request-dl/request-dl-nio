//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// Schedules a download that keeps running even if the app is suspended or terminated, via
/// `URLSession`'s background transfer support.
///
/// Unlike ``DownloadTask``, ``result()`` does not wait for the download to finish -- it can't:
/// the transfer may complete long after this call returns, in a different process launch
/// entirely. Register ``BackgroundDownloads/onEvent`` to be told when it actually completes,
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
/// -- none of them need a Keychain round-trip to survive a relaunch, only the certificate bytes
/// themselves, which travel alongside `id`/`destination` in the scheduled task's own state. A
/// client certificate (mTLS) is different: see ``BackgroundDownloadUnsupportedConfigurationError``
/// for why that's still rejected.
public struct BackgroundDownloadTask<Content: Property> {

    // MARK: - Private properties

    private let id: String
    private let destination: URL
    private let content: Content

    // MARK: - Inits

    /// - Parameters:
    ///   - id: Identifies this download in every ``BackgroundDownloads/Event`` it produces.
    ///     Not the `URLSession` background session identifier, which RequestDL manages
    ///     internally -- this is only ever your own correlation key.
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
    }

    // MARK: - Public methods

    /// Resolves `content` and schedules the download. Returns as soon as it's scheduled --
    /// use ``BackgroundDownloads/onEvent`` to observe how it turns out.
    ///
    /// - Throws: ``BackgroundDownloadUnsupportedConfigurationError`` if `content` configures a
    ///   client certificate (mTLS), or any error `content` itself throws while being resolved
    ///   into a request (an invalid URL, a certificate file that can't be read, etc.) -- the same
    ///   errors any other task can throw at this stage.
    public func result() async throws {
        let resolved = try await Resolve(
            root: content,
            environment: RequestEnvironmentValues.current
        ).build()

        let serverTrust = try resolved.session.configuration.secureConnection.map {
            (secureConnection: Internals.SecureConnection) -> Internals.ServerTrustPolicy.Descriptor in
            guard secureConnection.certificateChain == nil, secureConnection.privateKey == nil else {
                throw BackgroundDownloadUnsupportedConfigurationError()
            }

            return try Internals.ServerTrustPolicy.resolve(from: secureConnection).descriptor
        }

        let request = try resolved.requestConfiguration.buildURLRequestWithoutBody()

        BackgroundDownloads.Session.shared.schedule(
            request: request,
            id: id,
            destination: destination,
            serverTrust: serverTrust
        )
    }
}

#endif
