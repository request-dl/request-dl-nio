//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

extension Internals {

    /// Portable mirror of `NIOSSL.TLSVersion`, named to match it directly (`.tlsv12`, not
    /// `RequestDL.TLSVersion`'s own `.v1_2`) since this type's only consumers are
    /// `Internals.SecureConnection` and the NIO-only build path that converts it back.
    package enum TLSVersion: Sendable, Hashable {
        case tlsv1
        case tlsv11
        case tlsv12
        case tlsv13

        #if canImport(NIOCore)
        package func build() -> NIOSSL.TLSVersion {
            switch self {
            case .tlsv1:
                return .tlsv1
            case .tlsv11:
                return .tlsv11
            case .tlsv12:
                return .tlsv12
            case .tlsv13:
                return .tlsv13
            }
        }
        #endif
    }
}
