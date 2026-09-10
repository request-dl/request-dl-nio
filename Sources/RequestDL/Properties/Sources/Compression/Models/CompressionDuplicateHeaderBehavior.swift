//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// What ``Property/compression(_:onDuplicateHeader:shouldCompressBodyData:)`` does when the
/// request already carries a `Content-Encoding` header before compression would set its own.
///
/// This is a real conflict, not a footgun to design away: the request already carrying
/// `Content-Encoding` usually means the caller pre-compressed the body themselves (a file already
/// gzipped on disk, say) and set the header to declare that, a legitimate intent distinct from
/// asking this package to compress the body itself.
public enum CompressionDuplicateHeaderBehavior: Sendable, Hashable {

    /// Throws ``DuplicateContentEncodingError``. The default.
    case error

    /// Replaces the existing header value with the configured algorithm's.
    case replace

    /// Silently skips compression when the header already exists.
    case skip

    // MARK: - Internal methods

    func build() -> Internals.Compression.DuplicateHeaderBehavior {
        switch self {
        case .error:
            return .error
        case .replace:
            return .replace
        case .skip:
            return .skip
        }
    }
}
