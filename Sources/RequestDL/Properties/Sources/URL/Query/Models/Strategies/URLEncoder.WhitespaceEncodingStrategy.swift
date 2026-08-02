//
// See LICENSE for this package's licensing information.
//

extension URLEncoder {

    /// Defines strategies for encoding whitespace in a url encoded format.
    ///
    /// Applied last, after every name and value has been percent encoded. That ordering is what
    /// makes ``plus`` unambiguous: a literal `+` in the input is already `%2B` by the time this
    /// runs, so nothing else in the output can be mistaken for a space.
    public enum WhitespaceEncodingStrategy: URLEncodingStrategy {

        /// Replaces whitespace with `%20`.
        case percentEscaping

        /// Replaces whitespace with `+`.
        case plus

        /// Encodes whitespace using a custom closure that takes an `Encoder` as input parameter
        /// and throws an error.
        ///
        /// - Important: The closure must set ``URLEncoder/Encoder/whitespaceRepresentable``.
        /// Leaving it unset means there is no representation to substitute, and a literal space
        /// is not valid in a URL, so the encoder reports rather than emitting one.
        case custom(@Sendable (URLEncoder.Encoder) throws -> Void)

        // MARK: - Internal methods

        func encode(in encoder: URLEncoder.Encoder) throws {
            switch self {
            case .percentEscaping:
                encoder.whitespaceRepresentable = "%20"
            case .plus:
                encoder.whitespaceRepresentable = "+"
            case .custom(let closure):
                try closure(encoder)
            }
        }
    }
}
