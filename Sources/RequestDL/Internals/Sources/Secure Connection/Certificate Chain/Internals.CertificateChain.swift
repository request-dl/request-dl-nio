/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {

    enum CertificateChain: Sendable, Hashable {

        case certificates([Internals.Certificate])

        case bytes([UInt8])

        case file(String)

        // MARK: - Inits

        init() {
            self = .certificates([])
        }

        // MARK: - Internal methods

        mutating func append(_ certificate: Internals.Certificate) {
            switch self {
            case .file(let path):
                self = .certificates([.init(path, format: .pem), certificate])
            case .bytes(let bytes):
                self = .certificates([.init(bytes, format: .pem), certificate])
            case .certificates(let certificates):
                self = .certificates(certificates + [certificate])
            }
        }

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
}
