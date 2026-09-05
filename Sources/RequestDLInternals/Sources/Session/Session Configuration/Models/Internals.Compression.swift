//
// See LICENSE for this package's licensing information.
//

import NIOHTTPCompression

extension Internals {

    package enum Compression: Sendable, Hashable {

        case disabled
        case enabled(Internals.Compression.Algorithm)
    }
}

extension Internals.Compression {

    package enum Algorithm: Sendable, Hashable {

        case gzip
        case deflate

        // MARK: - Internal methods

        package func build() -> NIOCompression.Algorithm {
            switch self {
            case .gzip:
                return .gzip
            case .deflate:
                return .deflate
            }
        }
    }

    /// What to do when the request already carries a `Content-Encoding` header before
    /// compression would set its own. Mirrors `Session.DuplicateHeaderBehavior`, which is the
    /// public type this one is built from.
    package enum DuplicateHeaderBehavior: Sendable, Hashable {

        case error
        case replace
        case skip
    }
}
