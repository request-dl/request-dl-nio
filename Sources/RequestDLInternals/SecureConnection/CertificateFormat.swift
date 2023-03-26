/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public enum CertificateFormat {
    case der
    case pem
}

extension CertificateFormat {

    public var pathExtension: String {
        switch self {
        case .der:
            return "cer"
        case .pem:
            return "pem"
        }
    }
}

extension CertificateFormat {

    func build() -> NIOSSLSerializationFormats {
        switch self {
        case .der:
            return .der
        case .pem:
            return .pem
        }
    }
}
