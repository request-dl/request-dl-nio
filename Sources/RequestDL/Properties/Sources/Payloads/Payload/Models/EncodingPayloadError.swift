/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A structure representing an error that occurs during encoding payload.
public struct EncodingPayloadError: Error {

    /// An enumeration representing the different contexts of the error.
    public enum Context {

        /// The error occurred due to an invalid JSON object
        case invalidJSONObject

        /// The error occurred due to an invalid string encoding
        case invalidStringEncoding
    }

    /// The context of the error.
    public let context: Context

    /**
    Initializes a new instance of `EncodingPayloadError`.

    - Parameter context: The context of the error.
    */
    public init(_ context: Context) {
        self.context = context
    }
}
