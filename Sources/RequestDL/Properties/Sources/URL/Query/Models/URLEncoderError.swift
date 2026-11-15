//
// See LICENSE for this package's licensing information.
//

/// A structure representing an error that occurs during URL encoding.
public struct URLEncoderError: Error, Sendable, Hashable {

    /// An enumeration representing the different types of errors.
    ///
    /// - Note: Public as of 4.0, along with ``errorType``. The type was public while everything
    /// that described it was internal, so a caller could catch one of these and learn nothing
    /// from it. Matches ``EncodingPayloadError``, which was already inspectable.
    public enum ErrorType: Sendable, Hashable {

        /// A container was read before anything was written to it, or a strategy finished
        /// without producing the half it is responsible for.
        case unset

        /// A container was written to twice. Each one writes once.
        case alreadySet

        /// A whitespace strategy finished without setting a representation to substitute.
        case unsetWhitespaceRepresentable

        /// A `Date` could not be encoded with the chosen strategy: it is NaN, infinite or so far
        /// from 1970 that its seconds (or milliseconds) do not fit in a 64-bit integer.
        case invalidDate
    }

    /// The type of the error.
    public let errorType: ErrorType

    ///
    /// Initializes a new instance of `URLEncoderError`.
    ///
    /// - Parameter errorType: The type of the error.
    ///
    init(_ errorType: ErrorType) {
        self.errorType = errorType
    }
}

// MARK: - CustomStringConvertible

extension URLEncoderError: CustomStringConvertible {

    public var description: String {
        switch errorType {
        case .unset:
            return "The URL encoding container was read before a value was written to it"
        case .alreadySet:
            return "The URL encoding container was written to more than once"
        case .unsetWhitespaceRepresentable:
            return "The whitespace strategy did not set a representation for the space character"
        case .invalidDate:
            return "The date is not finite or is too far from 1970 to be encoded with the chosen strategy"
        }
    }
}
