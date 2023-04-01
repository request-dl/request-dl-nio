/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {

    enum TrustRoots: Equatable {

        case `default`

        case file(String)

        case bytes([UInt8])

        case certificates([Internals.Certificate])
    }
}

extension Internals.TrustRoots {

    init() {
        self = .certificates([])
    }

    mutating func append(_ certificate: Internals.Certificate) {
        guard case .certificates(let certificates) = self else {
            fatalError()
        }

        self = .certificates(certificates + [certificate])
    }
}

extension Internals.TrustRoots {

    func build() throws -> NIOSSLTrustRoots {
        switch self {
        case .default:
            return .default
        case .file(let file):
            return .file(file)
        case .bytes(let bytes):
            return .certificates(try NIOSSLCertificate.fromPEMBytes(bytes))
        case .certificates(let certificates):
            return .certificates(try certificates.map {
                try $0.build()
            })
        }
    }
}
