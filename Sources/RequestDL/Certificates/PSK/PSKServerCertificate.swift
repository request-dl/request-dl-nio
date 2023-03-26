/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

public struct PSKServerCertificate {

    public let key: SecureBytes

    public init(_ key: SecureBytes) {
        self.key = key
    }
}

extension PSKServerCertificate {

    func build() -> PSKServerIdentityResponse {
        .init(key: key)
    }
}
