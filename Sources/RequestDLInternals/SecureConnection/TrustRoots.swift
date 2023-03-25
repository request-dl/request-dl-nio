/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public enum TrustRoots {
    case `default`
    case file(String)
    case certificate(CertificateSource)
}

extension TrustRoots {

    func build() throws -> NIOSSLTrustRoots {
        switch self {
        case .default:
            return .default
        case .file(let file):
            return .file(file)
        case .certificate(let source):
            return try .certificates(source.build())
        }
    }
}
