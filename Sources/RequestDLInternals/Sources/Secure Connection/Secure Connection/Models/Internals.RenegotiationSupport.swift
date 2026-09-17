//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

extension Internals {

    /// Portable mirror of `NIOSSL.NIORenegotiationSupport`.
    package enum RenegotiationSupport: Sendable, Hashable {
        case none
        case once
        case always

        #if canImport(NIOCore)
        package func build() -> NIOSSL.NIORenegotiationSupport {
            switch self {
            case .none:
                return .none
            case .once:
                return .once
            case .always:
                return .always
            }
        }
        #endif
    }
}
