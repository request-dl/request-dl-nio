/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public enum CertificateChain: Equatable {

    case certificates([Certificate])

    case bytes([UInt8])

    case file(String)
}

extension CertificateChain {

    public init() {
        self = .certificates([])
    }

    public mutating func append(_ certificate: Certificate) {
        guard case .certificates(let certificates) = self else {
            fatalError()
        }

        self = .certificates(certificates + [certificate])
    }
}

extension CertificateChain {

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
