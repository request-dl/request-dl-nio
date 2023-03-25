/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public enum AdditionalTrustRootSource {
    case file(String)
    case certificate(CertificateSource)
}

extension AdditionalTrustRootSource {

    func build() throws -> NIOSSLAdditionalTrustRoots {
        switch self {
        case .file(let file):
            return .file(file)
        case .certificate(let source):
            return try .certificates(source.build())
        }
    }
}
