/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 An error type thrown by the `FlexibleURL` property when URL processing fails.

 This error provides context about the specific reason the url string could not be processed.
 */
public struct FlexibleURLError: Error {

    /**
     Defines the specific context or reason why the `FlexibleURL` processing failed.

     - `invalidURL`: Indicates that the provided url string could not be parsed as a valid URL structure.
     - `invalidHost`: Indicates that a required host component was missing or invalid when constructing a base URL.
     */
    public enum Context: Sendable {
        /// The provided string could not be interpreted as a valid URL.
        case invalidURL
        /// A host component was expected but was missing or invalid.
        case invalidHost
    }

    /// The contextual reason for the error.
    public let context: Context

    /// The original url string that caused the error.
    public let url: String

    /**
     Creates a new `FlexibleURLError`.

     - Parameters:
       - context: The reason for the error (e.g., invalid URL or host).
       - url: The url string that led to the error.
     */
    public init(
        context: Context,
        url: String
    ) {
        self.context = context
        self.url = url
    }
}
