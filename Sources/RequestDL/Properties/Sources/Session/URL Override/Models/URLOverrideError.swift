//
// See LICENSE for this package's licensing information.
//

/// An error type thrown by the `URLOverride` property when an origin or destination string
/// cannot be parsed.
///
/// This error provides context about the specific reason the string could not be processed.
public struct URLOverrideError: Error {

    ///
    /// Defines the specific context or reason why the `URLOverride` processing failed.
    ///
    /// - `invalidURL`: Indicates that the provided string could not be parsed as a valid URL structure.
    /// - `missingScheme`: Indicates the string did not include a scheme (e.g. `"https"`).
    /// - `missingHost`: Indicates the string did not include a host.
    ///
    public enum Context: Sendable {
        /// The provided string could not be interpreted as a valid URL.
        case invalidURL
        /// The scheme component was missing or empty.
        case missingScheme
        /// The host component was missing or empty.
        case missingHost
    }

    /// The contextual reason for the error.
    public let context: Context

    /// The original string that caused the error.
    public let url: String

    ///
    /// Creates a new `URLOverrideError`.
    ///
    /// - Parameters:
    ///   - context: The reason for the error (e.g. invalid URL or a missing scheme/host).
    ///   - url: The string that led to the error.
    ///
    public init(
        context: Context,
        url: String
    ) {
        self.context = context
        self.url = url
    }
}
