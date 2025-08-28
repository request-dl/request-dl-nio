/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {

    enum AdditionalTrustRoots: Sendable, Hashable {

        case file(String)

        case bytes([UInt8])

        case certificates([Internals.Certificate])

        // MARK: - Inits

        init() {
            self = .certificates([])
        }

        // MARK: - Internal methods

        mutating func append(_ certificate: Internals.Certificate) {
            guard case .certificates(let certificates) = self else {
                Internals.Log.failure(
                    .expectingCertificatesCase(self)
                )
            }

            self = .certificates(certificates + [certificate])
        }

        func build() throws -> NIOSSLAdditionalTrustRoots {
            switch self {
            case .file(let file):
                return .file(file)
            case .bytes(let bytes):
                return try .certificates(NIOSSLCertificate.fromPEMBytes(bytes))
            case .certificates(let certificates):
                return .certificates(try certificates.reduce(into: []) {
                    try $0.append(contentsOf: $1.build())
                })
            }
        }
    }
}
