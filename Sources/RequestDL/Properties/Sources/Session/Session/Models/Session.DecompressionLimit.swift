//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

extension Session {

    /// How far a native gzip/deflate decoder may expand a response on `.nio` and
    /// `.nioTransportServices`.
    public enum DecompressionLimit: Sendable, Hashable {

        /// No limit. This is the default.
        case none

        /// Refuses a response that expands past this many times its compressed size.
        case ratio(Int)

        /// Refuses a response that expands past this many bytes.
        case size(Int)

        // MARK: - Internal methods

        func build() -> Internals.Decompression.Limit {
            switch self {
            case .none:
                return .none
            case .ratio(let value):
                return .ratio(value)
            case .size(let value):
                return .size(value)
            }
        }
    }
}
