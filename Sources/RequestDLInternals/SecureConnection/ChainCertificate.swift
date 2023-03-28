/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct ChainCertificate: Equatable {

    private(set) var sources: [CertificateSource]

    public init(_ sources: [CertificateSource]) {
        self.sources = sources
    }

    public init() {
        self.init([])
    }

    public mutating func append(_ source: CertificateSource) {
        sources.append(source)
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
