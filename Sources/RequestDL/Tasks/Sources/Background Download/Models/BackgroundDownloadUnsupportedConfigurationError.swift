//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import protocol Foundation.LocalizedError
#endif

/// An error thrown when a ``BackgroundDownloadTask``'s content configures a ``SecureConnection``.
///
/// A background download can outlive the process that started it -- the delegate answering a TLS
/// challenge after the app relaunches has no access to the `Property` tree the request was
/// originally built from, only to whatever survives on the `URLSessionTask` itself. Rebuilding a
/// client identity (mTLS) would need a Keychain round-trip redone from scratch at relaunch time,
/// and rebuilding custom trust roots would need their source files re-resolved independently of
/// any in-memory state -- neither is implemented yet, so a request that needs either is rejected
/// up front rather than allowed to silently misbehave after the first relaunch.
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
        BackgroundDownloadTask does not support SecureConnection -- a background download can \
        outlive the process that started it, and there is no way yet to rebuild a client \
        identity or custom trust roots after a relaunch. Remove SecureConnection from this \
        request, or use DownloadTask instead if it needs to run in the foreground.
        """
    }
}

#endif
