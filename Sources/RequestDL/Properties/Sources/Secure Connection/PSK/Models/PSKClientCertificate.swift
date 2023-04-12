/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/// A struct representing a pre-shared key (PSK) client certificate.
public struct PSKClientCertificate {

    /// The PSK client certificate key.
    public let key: NIOSSL.NIOSSLSecureBytes

    /// The identity associated with the PSK client certificate.
    public let identity: String

    /// Creates a PSK client certificate with the given key and identity.
    ///
    /// - Parameters:
    ///   - key: The key for the PSK client certificate.
    ///   - identity: The identity associated with the PSK client certificate.
    public init(key: NIOSSL.NIOSSLSecureBytes, identity: String) {
        self.key = key
        self.identity = identity
    }
}

extension PSKClientCertificate {

    func build() -> NIOSSL.PSKClientIdentityResponse {
        .init(
            key: key,
            identity: identity
        )
    }
}
