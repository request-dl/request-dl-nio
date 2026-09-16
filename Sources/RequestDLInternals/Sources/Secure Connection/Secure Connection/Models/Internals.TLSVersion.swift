//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

#if canImport(Network)
import Network
#endif

extension Internals {

    /// Portable mirror of `NIOSSL.TLSVersion`, named to match it directly (`.tlsv12`, not
    /// `RequestDL.TLSVersion`'s own `.v1_2`) since this type's two consumers are
    /// `Internals.SecureConnection`'s NIO-only `build()` and `.urlSession`'s own
    /// `buildURLSessionConfiguration()`, and each converts this back to a different target type.
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

        #if canImport(Network)
        /// `URLSessionConfiguration.tlsMinimumSupportedProtocolVersion`/
        /// `tlsMaximumSupportedProtocolVersion`'s type, converted straight from this portable
        /// mirror with no detour through `NIOSSL.TLSVersion`, so `.urlSession`'s own
        /// config-building path never needs NIOSSL just to reach a Network.framework enum.
        /// Present unconditionally on every platform this package targets (iOS 13/macOS 10.15,
        /// both below this package's own deployment floor), so there's no availability branch to
        /// take here the way AsyncHTTPClient's own NIOTransportServices bridge still needs for
        /// its pre-iOS-13 `SSLProtocol` fallback.
        ///
        /// - Note: `.tlsv1`/`.tlsv11` map to deprecated (macOS 12+, not unavailable)
        /// `tls_protocol_version_t` cases, mirrored here anyway, deliberately: a caller who
        /// explicitly asked for TLS 1.0/1.1 (interop with a legacy server, say) gets the same
        /// answer under `.urlSession`, not a silent upgrade to whatever Apple currently
        /// recommends instead.
        package var urlSessionProtocolVersion: tls_protocol_version_t {
            switch self {
            case .tlsv1: return .TLSv10
            case .tlsv11: return .TLSv11
            case .tlsv12: return .TLSv12
            case .tlsv13: return .TLSv13
            }
        }
        #endif
    }
}
