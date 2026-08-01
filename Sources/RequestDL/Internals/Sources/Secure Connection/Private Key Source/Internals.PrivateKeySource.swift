//
// See LICENSE for this package's licensing information.
//

import NIOSSL

extension Internals {

    enum PrivateKeySource: Sendable, Equatable {

        case privateKey(PrivateKey)

        // MARK: - Internal methods

        func build() throws -> NIOSSL.NIOSSLPrivateKeySource {
            switch self {
            case .privateKey(let privateKey):
                return try .privateKey(privateKey.build())
            }
        }
    }
}
