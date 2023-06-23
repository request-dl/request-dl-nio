/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// An error type representing a request with no response.
public struct RequestFailureError: LocalizedError {

    public var errorDescription: String? {
        "The request received no response."
    }

    /// Creates the error.
    public init() {}
}
