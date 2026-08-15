//
// See LICENSE for this package's licensing information.
//

import NIOHTTPCompression

extension Internals {

    enum Compression: Sendable, Hashable {

        case disabled
        case enabled(Internals.Compression.Algorithm)
    }
}

extension Internals.Compression {

    enum Algorithm: Sendable, Hashable {

        case gzip
        case deflate

        // MARK: - Internal methods

        func build() -> NIOCompression.Algorithm {
            switch self {
            case .gzip:
                return .gzip
            case .deflate:
                return .deflate
            }
        }
    }
}
