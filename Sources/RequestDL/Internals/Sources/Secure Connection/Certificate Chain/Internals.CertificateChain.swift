/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {

    enum CertificateChain: Hashable {

        case certificates([Internals.Certificate])

        case bytes([UInt8])

        case file(String)
    }
}

extension Internals.CertificateChain {

    init() {
        self = .certificates([])
    }

    mutating func append(_ certificate: Internals.Certificate) {
        guard case .certificates(let certificates) = self else {
            Internals.Log.failure(
                .expectingCertificatesCase(self)
            )
        }

        self = .certificates(certificates + [certificate])
    }
}

extension Internals.CertificateChain {

    func build() throws -> [NIOSSLCertificateSource] {
        switch self {
        case .certificates(let certificates):
            return try certificates.map {
                .certificate(try $0.build())
            }
        case .bytes(let bytes):
            return try NIOSSLCertificate.fromPEMBytes(bytes).map {
                .certificate($0)
            }
        case .file(let file):
            return try NIOSSLCertificate.fromPEMFile(file).map {
                .certificate($0)
            }
        }
    }
}
