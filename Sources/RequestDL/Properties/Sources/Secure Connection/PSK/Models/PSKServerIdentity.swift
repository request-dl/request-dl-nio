/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/// A struct representing a pre-shared key (PSK) server.
@available(*, deprecated, renamed: "SSLPSKServerIdentityResolver")
public struct PSKServerIdentity {

    /// The PSK server key.
    public let key: NIOSSL.NIOSSLSecureBytes

    /// Creates a PSK server with the given key.
    ///
    /// - Parameter key: The key for the PSK server.
    public init(_ key: NIOSSL.NIOSSLSecureBytes) {
        self.key = key
    }
}

@available(*, deprecated, renamed: "SSLPSKServerIdentityResolver")
extension PSKServerIdentity {

    func build() -> NIOSSL.PSKServerIdentityResponse {
        .init(key: key)
    }
}
