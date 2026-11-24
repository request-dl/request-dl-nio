//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSOCKS
#endif

#if canImport(Darwin)
import Foundation
#endif

extension Internals {

    /// A SOCKS5 proxy rejected the user name and the password it was given (RFC 1929), the same
    /// whichever executor ran the request.
    ///
    /// `.urlSession` raises it itself, from the `EAUTH` CFNetwork ends the connection with; for
    /// `.nio` and `.nioTransportServices` it is what the fork's `SOCKSError.AuthenticationFailed`
    /// becomes (see ``translating(_:)``), at the same places `RedirectError.translating(_:)`
    /// runs. `RawTask` and `AsyncResponse` turn it into the public `ProxyAuthorizationError`.
    ///
    /// The native error is kept as ``underlying``: it holds the status the proxy answered with
    /// or the errno, never the credentials.
    package struct SOCKSAuthenticationRejectedError: Swift.Error, Sendable, CustomStringConvertible {

        // MARK: - Internal properties

        /// The error the executor reported.
        package let underlying: any Swift.Error

        package var description: String {
            "The SOCKS proxy rejected the user name and the password it was given."
        }

        // MARK: - Inits

        package init(underlying: any Swift.Error) {
            self.underlying = underlying
        }
    }
}

#if canImport(NIOCore)

extension Internals.SOCKSAuthenticationRejectedError {

    /// `error` as this type when it is the SOCKS client's own for a rejected user name and
    /// password, and `error` itself otherwise.
    package static func translating(_ error: any Error) -> any Error {
        guard error is SOCKSError.AuthenticationFailed else {
            return error
        }

        return Internals.SOCKSAuthenticationRejectedError(underlying: error)
    }
}

#endif

#if canImport(Darwin)

extension Internals.SOCKSAuthenticationRejectedError {

    /// Whether `error` is what CFNetwork ends a connection with when a SOCKS5 proxy rejects the
    /// credentials: `NSPOSIXErrorDomain` and `EAUTH`.
    ///
    /// Observed, not documented (see `InternalsURLSessionClientSOCKSAuthenticationTests`), so it
    /// is only trusted for a session that did send credentials to a SOCKS proxy.
    package static func isURLSessionRejection(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == NSPOSIXErrorDomain && error.code == Int(EAUTH)
    }
}

#endif
