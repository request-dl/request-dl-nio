//
// See LICENSE for this package's licensing information.
//

/// Something in a curl command line couldn't be parsed.
///
/// `CURLTask` only supports a documented subset of curl's flags — see ``CURLTask`` — so anything
/// outside that subset surfaces here rather than being silently dropped.
public struct CURLParsingError: Error, Sendable, Hashable {

    /// What went wrong.
    public enum Context: Sendable, Hashable {

        /// A flag outside the documented subset (`-X`/`-H`/`-d`/`-F`/`-u`/`--url`/`-G`, plus
        /// their long forms).
        case unsupportedFlag

        /// A flag that takes a value was the last token, or its value didn't parse (a `-F`
        /// field with no `=`, a `-u` credential with no `:`, ...).
        case malformedArgument

        /// No `--url`, bare trailing URL, or `-G` target was present.
        case missingURL

        /// A quoted argument was never closed.
        case unterminatedQuote

        /// A trailing `\` had nothing after it to escape.
        case danglingEscape
    }

    /// What went wrong.
    public let context: Context

    /// The offending token, when the failure is tied to one (absent for ``Context/missingURL``).
    public let token: String?

    init(_ context: Context, token: String? = nil) {
        self.context = context
        self.token = token
    }
}

// MARK: - CustomStringConvertible

extension CURLParsingError: CustomStringConvertible {

    public var description: String {
        switch context {
        case .unsupportedFlag:
            return "Unsupported curl flag: \(token ?? "")"
        case .malformedArgument:
            return "Malformed curl argument: \(token ?? "")"
        case .missingURL:
            return "No URL found in the curl command"
        case .unterminatedQuote:
            return "Unterminated quote in the curl command"
        case .danglingEscape:
            return "Trailing backslash with nothing to escape"
        }
    }
}
