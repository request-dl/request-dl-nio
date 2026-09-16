//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

extension Internals {

    package enum PrivateKeySource: Sendable, Equatable {

        case privateKey(PrivateKey)

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() throws -> NIOSSL.NIOSSLPrivateKeySource {
            switch self {
            case .privateKey(let privateKey):
                return try .privateKey(privateKey.build())
            }
        }
        #endif
    }
}
