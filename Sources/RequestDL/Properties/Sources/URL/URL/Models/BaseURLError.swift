/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A custom error type representing base URL-related errors.

 ```swift
 throw BaseURLError(
    context: .invalidHost,
    baseURL: "http://example.com"
 )
 ```
 */
@available(*, deprecated, renamed: "EndpointURL")
public struct BaseURLError: LocalizedError {

    /**
     The possible contexts for the base URL error.
     */
    public enum Context: Sendable {
        /// The host string provided is invalid, as it should not include the protocol.
        case invalidHost

        /// The host string has an unexpected format and the host could not be extracted.
        case unexpectedHost
    }

    // MARK: - Public properties

    /// The context of the error.
    public let context: Context

    /// The base URL associated with the error.
    public let baseURL: String

    public var errorDescription: String? {
        switch context {
        case .invalidHost:
            return """
                Invalid host string: The url scheme should not be \
                included; BaseURL: \(baseURL)
                """
        case .unexpectedHost:
            return """
                Unexpected format for host string: Could not extract the \
                host; BaseURL: \(baseURL)
                """
        }
    }

    // MARK: - Initializer

    /**
     Initializes a `BaseURLError` instance.

     - Parameters:
        - context: The context of the error.
        - baseURL: The base URL associated with the error.
     */
    public init(
        context: Context,
        baseURL: String
    ) {
        self.context = context
        self.baseURL = baseURL
    }
}
