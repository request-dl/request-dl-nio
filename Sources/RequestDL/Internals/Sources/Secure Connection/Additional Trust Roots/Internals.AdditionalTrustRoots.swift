/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {

    enum AdditionalTrustRoots: Hashable {

        case file(String)

        case bytes([UInt8])

        case certificates([Internals.Certificate])
    }
}

extension Internals.AdditionalTrustRoots {

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

extension Internals.AdditionalTrustRoots {

    func build() throws -> NIOSSLAdditionalTrustRoots {
        switch self {
        case .file(let file):
            return .file(file)
        case .bytes(let bytes):
            return try .certificates(NIOSSLCertificate.fromPEMBytes(bytes))
        case .certificates(let certificates):
            return .certificates(try certificates.map {
                try $0.build()
            })
        }
    }
}
