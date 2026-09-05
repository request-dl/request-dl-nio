//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

extension Session {

    /// What ``Session/compression(_:onDuplicateHeader:)`` does when the request already carries
    /// a `Content-Encoding` header before compression would set its own.
    public enum DuplicateHeaderBehavior: Sendable, Hashable {

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
}
