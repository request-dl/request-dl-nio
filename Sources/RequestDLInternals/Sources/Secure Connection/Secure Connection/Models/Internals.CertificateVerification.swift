//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

extension Internals {

    /// Portable mirror of `NIOSSL.CertificateVerification` — `Internals.SecureConnection`'s own
    /// currency for this knob, since it's read by `Internals.ServerTrustPolicy`/
    /// `Internals.NIOTrustEvaluator` regardless of whether NIO is available.
    package enum CertificateVerification: Sendable, Hashable {
        case none
        case noHostnameVerification
        case fullVerification

        #if canImport(NIOCore)
        package func build() -> NIOSSL.CertificateVerification {
            switch self {
            case .none:
                return .none
            case .noHostnameVerification:
                return .noHostnameVerification
            case .fullVerification:
                return .fullVerification
            }
        }
        #endif
    }
}
