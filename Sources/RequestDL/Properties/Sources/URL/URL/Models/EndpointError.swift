/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 An error type thrown by the `Endpoint` property when URL processing fails.

 This error provides context about the specific reason the endpoint string could not be processed.
 */
public struct EndpointError: Error {

    /**
     Defines the specific context or reason why the `Endpoint` processing failed.

     - `invalidURL`: Indicates that the provided endpoint string could not be parsed as a valid URL structure.
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

    /// The original endpoint string that caused the error.
    public let url: String

    /**
     Creates a new `EndpointError`.

     - Parameters:
       - context: The reason for the error (e.g., invalid URL or host).
       - url: The endpoint string that led to the error.
     */
    public init(
        context: Context,
        url: String
    ) {
        self.context = context
        self.url = url
    }
}
