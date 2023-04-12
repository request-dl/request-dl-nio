/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/**
 An enumeration that represents different options for renegotiation support in the context of TLS.

 `RenegotiationSupport` is used as a property inside the SecureConnection structure to specify the
 rules for renegotiation support in the context of Transport Layer Security (TLS) in Swift.
*/
public enum RenegotiationSupport {

    /// Indicates that renegotiation is not supported.
    case none

    /// Indicates that renegotiation is supported, but only once.
    case once

    /// Indicates that renegotiation is supported always.
    case always
}

extension RenegotiationSupport {

    func build() -> NIOSSL.NIORenegotiationSupport {
        switch self {
        case .none:
            return .none
        case .once:
            return .once
        case .always:
            return .always
        }
    }
}
