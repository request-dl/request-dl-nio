/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Certificate {

    public enum Format {
        case der
        case pem
    }
}

extension Certificate.Format {

    public var pathExtension: String {
        switch self {
        case .der:
            return "cer"
        case .pem:
            return "pem"
        }
    }
}

extension Certificate.Format {

    func build() -> NIOSSLSerializationFormats {
        switch self {
        case .der:
            return .der
        case .pem:
            return .pem
        }
    }
}
