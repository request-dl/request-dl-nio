/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals.Certificate {

    enum Format: Sendable, Hashable {

        case der
        case pem

        // MARK: - Internal properties

        var pathExtension: String {
            switch self {
            case .der:
                return "cer"
            case .pem:
                return "pem"
            }
        }

        // MARK: - Internal methods

        func build() -> NIOSSLSerializationFormats {
            switch self {
            case .der:
                return .der
            case .pem:
                return .pem
            }
        }
    }
}
