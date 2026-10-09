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

    /// Replaces the existing header value with the configured algorithm's, and compresses the
    /// body.
    ///
    /// Meant for a header that is stale or wrong, on a body that is not encoded yet. It is not
    /// for a body that was already compressed: that body is compressed a second time while the
    /// header names only the new algorithm, so the server decodes once and is left with the first
    /// layer. Use ``skip`` for a body that was compressed by the caller.
    case replace

    /// Silently skips compression when the header already exists, sending the body and the header
    /// exactly as they are.
    ///
    /// The choice for a body the caller compressed themselves (a file already gzipped on disk,
    /// say).
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
