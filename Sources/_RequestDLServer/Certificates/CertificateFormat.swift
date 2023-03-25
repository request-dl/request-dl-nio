/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public enum CertificateFormat {
    case der
    case pem
}

extension CertificateFormat {

    var `extension`: String {
        switch self {
        case .der:
            return "cer"
        case .pem:
            return "pem"
        }
    }
}
