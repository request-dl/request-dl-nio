/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/// A struct representing a pre-shared key (PSK) client.
@available(*, deprecated, renamed: "SSLPSKClientIdentityResolver")
public struct PSKClientIdentity {

    /// The PSK client key.
    public let key: NIOSSL.NIOSSLSecureBytes

    /// The identity associated with the PSK client.
    public let identity: String

    /// Creates a PSK client with the given key and identity.
    ///
    /// - Parameters:
    ///   - key: The key for the PSK client.
    ///   - identity: The identity associated with the PSK client.
    public init(key: NIOSSL.NIOSSLSecureBytes, identity: String) {
        self.key = key
        self.identity = identity
    }
}

@available(*, deprecated, renamed: "SSLPSKClientIdentityResolver")
extension PSKClientIdentity {

    func build() -> NIOSSL.PSKClientIdentityResponse {
        .init(
            key: key,
            identity: identity
        )
    }
}
