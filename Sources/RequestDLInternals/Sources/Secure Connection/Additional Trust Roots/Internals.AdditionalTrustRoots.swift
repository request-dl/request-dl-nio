//
// See LICENSE for this package's licensing information.
//

import NIOSSL

extension Internals {

    package enum AdditionalTrustRoots: Sendable, Hashable {

        case file(String)

        case bytes([UInt8])

        case certificates([Internals.Certificate])

        // MARK: - Inits

        package init() {
            self = .certificates([])
        }

        // MARK: - Internal methods

        package mutating func append(_ certificate: Internals.Certificate) {
            switch self {
            case .file(let path):
                self = .certificates([.init(path, format: .pem), certificate])
            case .bytes(let bytes):
                self = .certificates([.init(bytes, format: .pem), certificate])
            case .certificates(let certificates):
                self = .certificates(certificates + [certificate])
            }
        }

        package func build() throws -> NIOSSLAdditionalTrustRoots {
            switch self {
            case .file(let file):
                return .file(file)
            case .bytes(let bytes):
                return try .certificates(NIOSSLCertificate.fromPEMBytes(bytes))
            case .certificates(let certificates):
                return .certificates(
                    try certificates.reduce(into: []) {
                        try $0.append(contentsOf: $1.build())
                    }
                )
            }
        }
    }
}
