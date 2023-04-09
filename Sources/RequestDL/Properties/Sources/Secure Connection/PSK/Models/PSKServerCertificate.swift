/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct PSKServerCertificate {

    public let key: NIOSSL.NIOSSLSecureBytes

    public init(_ key: NIOSSL.NIOSSLSecureBytes) {
        self.key = key
    }
}

extension PSKServerCertificate {

    func build() -> NIOSSL.PSKServerIdentityResponse {
        .init(key: key)
    }
}
