/*
 See LICENSE for this package's licensing information.
 */

import Foundation
import NIOSSL

extension Internals {

    enum TrustRoots: Sendable, Hashable {

        case `default`

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

        func build() throws -> NIOSSLTrustRoots {
            switch self {
            case .default:
                return .default
            case .file(let file):
                return .file(file)
            case .bytes(let bytes):
                return .certificates(try NIOSSLCertificate.fromPEMBytes(bytes))
            case .certificates(let certificates):
                return .certificates(try certificates.reduce(into: []) {
                    try $0.append(contentsOf: $1.build())
                })
            }
        }
    }
}
