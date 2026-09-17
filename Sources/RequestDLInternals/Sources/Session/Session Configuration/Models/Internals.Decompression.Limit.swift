//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOHTTPCompression
#endif

extension Internals.Decompression {

    package enum Limit: Sendable, Hashable {

        case none
        case size(Int)
        case ratio(Int)

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() -> NIOHTTPDecompression.DecompressionLimit {
            switch self {
            case .none:
                return .none
            case .ratio(let value):
                return .ratio(value)
            case .size(let value):
                return .size(value)
            }
        }
        #endif
    }
}
