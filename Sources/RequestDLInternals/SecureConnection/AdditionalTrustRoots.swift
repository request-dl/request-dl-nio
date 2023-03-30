/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public enum AdditionalTrustRoots: Equatable {

    case file(String)

    case bytes([UInt8])

    case certificates([Certificate])
}

extension AdditionalTrustRoots {

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

extension AdditionalTrustRoots {

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
