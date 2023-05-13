/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct URLEncoderError: Error {

    enum ErrorType {
        case unset
        case alreadySet
    }

    // MARK: - Internal properties

    let errorType: ErrorType

    // MARK: - Inits

    init(_ errorType: ErrorType) {
        self.errorType = errorType
    }
}
