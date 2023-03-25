/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct ChainCertificate {

    let sources: [CertificateSource]

    public init(_ sources: [CertificateSource]) {
        self.sources = sources
    }
}

extension ChainCertificate {

    func build() throws -> [NIOSSLCertificateSource] {
        try sources.reduce([]) {
            try $0 + $1.build().map {
                .certificate($0)
            }
        }
    }
}
