//
// See LICENSE for this package's licensing information.
//

import NIOSSL

extension Internals.Certificate {

    package enum Format: Sendable, Hashable, Codable {

        case der
        case pem

        // MARK: - Internal properties

        package var pathExtension: String {
            switch self {
            case .der:
                return "cer"
            case .pem:
                return "pem"
            }
        }

        // MARK: - Internal methods

        package func build() -> NIOSSLSerializationFormats {
            switch self {
            case .der:
                return .der
            case .pem:
                return .pem
            }
        }
    }
}
