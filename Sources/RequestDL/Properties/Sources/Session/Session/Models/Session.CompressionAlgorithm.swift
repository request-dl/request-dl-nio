//
// See LICENSE for this package's licensing information.
//

extension Session {

    /// The algorithm used to compress the outgoing request body.
    public enum CompressionAlgorithm: Sendable, Hashable {

        case gzip
        case deflate

        // MARK: - Internal methods

        func build() -> Internals.Compression.Algorithm {
            switch self {
            case .gzip:
                return .gzip
            case .deflate:
                return .deflate
            }
        }
    }
}
