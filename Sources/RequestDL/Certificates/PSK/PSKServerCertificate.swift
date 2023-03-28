/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct PSKServerCertificate {

    public let key: SecureBytes

    public init(_ key: SecureBytes) {
        self.key = key
    }
}

extension PSKServerCertificate {

    func build() -> Internals.PSKServerIdentityResponse {
        .init(key: key)
    }
}
