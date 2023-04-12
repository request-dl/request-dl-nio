/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/// A struct representing a pre-shared key (PSK) server certificate.
public struct PSKServerCertificate {

    /// The PSK server certificate key.
    public let key: NIOSSL.NIOSSLSecureBytes

    /// Creates a PSK server certificate with the given key.
    ///
    /// - Parameter key: The key for the PSK server certificate.
    public init(_ key: NIOSSL.NIOSSLSecureBytes) {
        self.key = key
    }
}

extension PSKServerCertificate {

    func build() -> NIOSSL.PSKServerIdentityResponse {
        .init(key: key)
    }
}
