/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct URLEncoderError: Error {

    let errorType: ErrorType

    init(_ errorType: ErrorType) {
        self.errorType = errorType
    }
}

extension URLEncoderError {

    enum ErrorType {
        case unset
        case alreadySet
    }
}
