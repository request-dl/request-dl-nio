//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Why a ``CookieJar`` refused a cookie you inserted.
///
/// The cases say which part was wrong and carry nothing of the cookie, so an error is safe to log.
public enum CookieJarError: Error, Sendable, Equatable {

    /// The name is empty, has a control character, a `;` or a `=`, or starts or ends with a blank.
    case invalidName

    /// The value has a control character, a `;`, or starts or ends with a blank. A `;` is refused
    /// because it would put a second cookie in the `Cookie` header.
    case invalidValue

    /// The domain is empty, is not a host name or an IP address, or is an IP address for a cookie
    /// that is not host-only.
    case invalidDomain

    /// The path does not start with `/`, or has a control character or a `;`.
    case invalidPath

    /// The name and the value are together larger than 4096 bytes, or the domain or the path is
    /// larger than 1024.
    case tooLarge

    /// The cookie is not host-only and its domain is a single label (`com`) or a public suffix of
    /// the jar's ``PublicSuffixList`` (`co.uk`).
    case publicSuffix

    /// The name starts with `__Secure-` or `__Host-` and the cookie does not meet what that prefix
    /// requires: `Secure` for both, and for `__Host-` also host-only and the path `/`.
    case prefixRule
}

extension CookieJarError {

    init(_ rejection: Internals.Cookie.Rejection) {
        switch rejection {
        case .invalidName:
            self = .invalidName
        case .invalidValue:
            self = .invalidValue
        case .invalidDomain:
            self = .invalidDomain
        case .invalidPath:
            self = .invalidPath
        case .tooLarge:
            self = .tooLarge
        case .publicSuffix:
            self = .publicSuffix
        case .prefixRule:
            self = .prefixRule
        }
    }
}
