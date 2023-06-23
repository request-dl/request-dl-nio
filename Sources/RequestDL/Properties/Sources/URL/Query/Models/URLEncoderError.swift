/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A structure representing an error that occurs during URL encoding.
public struct URLEncoderError: Error {

    /// An enumeration representing the different types of errors.
    enum ErrorType {

        /// The error occurred because the value is unset.
        case unset

        /// The error occurred because the value is already set.
        case alreadySet
    }

    /// The type of the error.
    let errorType: ErrorType

    /**
    Initializes a new instance of `URLEncoderError`.

    - Parameter errorType: The type of the error.
    */
    init(_ errorType: ErrorType) {
        self.errorType = errorType
    }
}
