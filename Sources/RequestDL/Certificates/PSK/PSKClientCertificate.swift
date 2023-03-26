/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

public struct PSKClientCertificate {

    public let key: SecureBytes

    public let identity: String

    public init(key: SecureBytes, identity: String) {
        self.key = key
        self.identity = identity
    }
}

extension PSKClientCertificate {

    func build() -> PSKClientIdentityResponse {
        .init(
            key: key,
            identity: identity
        )
    }
}
