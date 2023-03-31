/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals.Certificate {

    enum Format {
        case der
        case pem
    }
}

extension Internals.Certificate.Format {

    var pathExtension: String {
        switch self {
        case .der:
            return "cer"
        case .pem:
            return "pem"
        }
    }
}

extension Internals.Certificate.Format {

    func build() -> NIOSSLSerializationFormats {
        switch self {
        case .der:
            return .der
        case .pem:
            return .pem
        }
    }
}
