/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct PSKClientCertificate {

    public let key: NIOSSL.NIOSSLSecureBytes

    public let identity: String

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
