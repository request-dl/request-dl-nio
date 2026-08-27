//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import protocol Foundation.LocalizedError
#endif

/// An error thrown when a ``BackgroundDownloadTask``'s content configures a client certificate
/// (mTLS) -- ``SecureConnection``'s `certificateChain`/`privateKey`.
///
/// A background download can outlive the process that started it -- the delegate answering a TLS
/// challenge after the app relaunches has no access to the `Property` tree the request was
/// originally built from, only to whatever survives on the `URLSessionTask` itself.
/// `TrustRoots`/`AdditionalTrustRoots`/``SecureConnection/verification(_:)`` all survive that fine
/// -- their certificate bytes travel with the scheduled task itself, the same way `id`/
/// `destination` do. A client identity does not: presenting one needs a `SecIdentity` built via a
/// Keychain round-trip, which would have to be redone from scratch after a relaunch, and isn't
/// implemented yet -- so a request that needs one is rejected up front, rather than allowed to
/// silently misbehave after the first relaunch.
public struct BackgroundDownloadUnsupportedConfigurationError: Error, Sendable {

    init() {}
}

// MARK: - LocalizedError

extension BackgroundDownloadUnsupportedConfigurationError: LocalizedError {

    public var errorDescription: String? {
        description
    }
}

// MARK: - CustomStringConvertible

extension BackgroundDownloadUnsupportedConfigurationError: CustomStringConvertible {

    public var description: String {
        """
        BackgroundDownloadTask does not support a client certificate (mTLS) -- a background \
        download can outlive the process that started it, and there is no way yet to rebuild a \
        client identity via a Keychain round-trip after a relaunch. TrustRoots/AdditionalTrustRoots \
        are supported; remove the client certificate/private key from this request, or use \
        DownloadTask instead if it needs to run in the foreground.
        """
    }
}

#endif
