/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public enum CertificateVerification: Sendable {

    case none

    case noHostnameVerification

    case fullVerification
}

extension CertificateVerification {

    func build() -> NIOSSL.CertificateVerification {
        switch self {
        case .none:
            return .none
        case .noHostnameVerification:
            return .noHostnameVerification
        case .fullVerification:
            return .fullVerification
        }
    }
}