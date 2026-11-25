//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// An error thrown when the ``ProxyAuthorization`` of a ``Proxy`` cannot be used with the proxy's
/// ``Proxy/ConnectionProtocol``, or when a SOCKS proxy rejects it.
///
/// Credentials a proxy cannot take are thrown while the request is being built, before anything
/// is sent, so they are never silently left out of the connection. A SOCKS5 proxy that rejects
/// the credentials it was given fails the request later, with ``Reason-swift.enum/socksAuthenticationRejected``.
///
/// A SOCKS5 proxy takes only a user name and a password (RFC 1929), not an HTTP
/// `Proxy-Authorization` header. ``ProxyAuthorization/basic(username:password:)`` is that user
/// name and password; ``ProxyAuthorization/basic(credentials:)`` (an already encoded header
/// value) and ``ProxyAuthorization/bearer(tokens:)`` are not, and are refused.
///
/// ```swift
/// do {
///     try await DataTask { ... }.result()
/// } catch let error as ProxyAuthorizationError where error.reason == .socksAuthenticationRejected {
///     // The proxy does not accept this user name and password.
/// }
/// ```
///
/// The error never carries the credentials, only what is wrong with them.
public struct ProxyAuthorizationError: Error, Sendable, Hashable {

    /// What is wrong with the authorization.
    public enum Reason: Sendable, Hashable {

        /// A SOCKS proxy was given ``ProxyAuthorization/basic(credentials:)`` or
        /// ``ProxyAuthorization/bearer(tokens:)``: both are HTTP header values, and SOCKS5
        /// authenticates with a user name and a password.
        case socksRequiresUsernameAndPassword

        /// The user name of a SOCKS5 proxy takes 1 to 255 bytes in UTF-8. `actual` is the
        /// number of bytes it has.
        case socksUsernameLength(actual: Int)

        /// The password of a SOCKS5 proxy takes 0 to 255 bytes in UTF-8 (an empty password is
        /// valid). `actual` is the number of bytes it has.
        case socksPasswordLength(actual: Int)

        /// The user name or the password of a SOCKS5 proxy has a NUL (`\0`) in it. SOCKS5 could
        /// carry it, but `URLSession` treats the credentials as C strings and would cut them
        /// there, so the proxy would be authenticated with other credentials than the NIO
        /// executors send. It is refused so that no executor does either.
        case socksCredentialsContainNUL

        /// A SOCKS5 proxy answered the user name and the password with a rejection (RFC 1929).
        ///
        /// The same on every executor. It is not retried, since sending the same wrong
        /// credentials again could only lock the account. A proxy that closes the connection
        /// right after receiving them, without answering, is taken for this too under `.nio` and
        /// `.nioTransportServices`.
        case socksAuthenticationRejected
    }

    // MARK: - Public properties

    /// What is wrong with the authorization.
    public let reason: Reason

    /// The error the executor reported, for ``Reason-swift.enum/socksAuthenticationRejected`` only.
    ///
    /// Under `.nio` and `.nioTransportServices` it is `SOCKSError.AuthenticationFailed` (from
    /// `NIOSOCKS`, which RequestDL does not re-export), and under `.urlSession` an `NSError` in
    /// `NSPOSIXErrorDomain` with code `EAUTH` (80). Neither carries the credentials. It is only
    /// for diagnosis: it is not part of the error's equality, which is its ``reason``, and what
    /// it is may change with the executor or the operating system.
    public let underlyingError: (any Error)?

    // MARK: - Inits

    init(_ error: Internals.SOCKSAuthenticationRejectedError) {
        self.reason = .socksAuthenticationRejected
        self.underlyingError = error.underlying
    }

    init(_ mismatch: Internals.Proxy.Authorization.Mismatch) {
        self.underlyingError = nil

        switch mismatch {
        case .httpShapeOnSOCKSProxy:
            self.reason = .socksRequiresUsernameAndPassword
        case .socksShapeOnHTTPProxy:
            // Unreachable from the public API: `ProxyAuthorization` has no SOCKS-only shape, and
            // `build(for:)` only makes `.socks` for a SOCKS proxy. Saying "SOCKS requires..." for
            // it would be a wrong message, so it is not mapped at all.
            preconditionFailure("A SOCKS authorization was built for an HTTP proxy.")
        case .socksCredentialContainsNUL:
            self.reason = .socksCredentialsContainNUL
        case .socksUsernameLength(let actual):
            self.reason = .socksUsernameLength(actual: actual)
        case .socksPasswordLength(let actual):
            self.reason = .socksPasswordLength(actual: actual)
        }
    }
}

// MARK: - Hashable

extension ProxyAuthorizationError {

    public static func == (lhs: ProxyAuthorizationError, rhs: ProxyAuthorizationError) -> Bool {
        lhs.reason == rhs.reason
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reason)
    }
}

// MARK: - CustomStringConvertible

extension ProxyAuthorizationError: CustomStringConvertible {

    public var description: String {
        switch reason {
        case .socksRequiresUsernameAndPassword:
            return """
                RequestDL could not use this proxy authorization with a SOCKS proxy: SOCKS5 \
                authenticates with a user name and a password, so only \
                ProxyAuthorization.basic(username:password:) can be used with it, not a raw \
                credentials string or a bearer token. The request was not sent.
                """

        case .socksUsernameLength(let actual):
            return """
                RequestDL could not use this proxy authorization with a SOCKS proxy: the user name \
                has \(actual) bytes in UTF-8, and SOCKS5 takes 1 to 255. The request was not sent.
                """

        case .socksPasswordLength(let actual):
            return """
                RequestDL could not use this proxy authorization with a SOCKS proxy: the password \
                has \(actual) bytes in UTF-8, and SOCKS5 takes 0 to 255. The request was not sent.
                """

        case .socksCredentialsContainNUL:
            return """
                RequestDL could not use this proxy authorization with a SOCKS proxy: the user name \
                or the password has a NUL character, which URLSession would cut the credentials at. \
                The request was not sent.
                """

        case .socksAuthenticationRejected:
            return """
                The SOCKS proxy rejected the user name and the password it was given, so the \
                request failed. It was not retried: sending the same credentials again could only \
                lock the account.
                """
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension ProxyAuthorizationError: CustomDebugStringConvertible {

    /// ``description``, followed by ``underlyingError`` when there is one, which is what
    /// `String(reflecting:)` and the debugger show.
    public var debugDescription: String {
        guard let underlyingError else {
            return description
        }

        return "\(description) Underlying error: \(String(reflecting: underlyingError))"
    }
}
