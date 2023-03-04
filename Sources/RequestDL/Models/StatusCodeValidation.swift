//
//  StatusCodeValidation.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

/**
 Enumeration for defining the types of HTTP status code validations.

 Usage:

 ```swift
 // Example of validating success and redirection codes.
 let validationType: StatusCodeValidation = .successAndRedirect

 // Example of custom status code validation.
 let validationType: StatusCodeValidation = .custom([400, 404, 422])
 ```

 The enumeration cases are:

 - `none`: No validation. This means all HTTP status codes are considered valid.
 - `success`: Validates only success codes (2xx). Any other HTTP status code will be considered invalid.
 - `successAndRedirect`: Validates success codes (2xx) and redirection codes (3xx).
 - `custom`: Validates only the status codes passed in the parameter. Any other HTTP
 status code will be considered invalid.

 The `statusCodes` property returns the list of HTTP status codes that should be considered valid, based on the
 enumeration case.

 The `validate(statusCode:)` method receives an HTTP status code and returns a boolean indicating whether
 it is considered valid, based on the validation type defined by the enumeration case.
 */
public enum StatusCodeValidation: Equatable {

    /// No validation. All HTTP status codes are considered valid.
    case none

    /// Validates only success codes (2xx). Any other HTTP status code will be considered invalid.
    case success

    /// Validates success codes (2xx) and redirection codes (3xx). Any other HTTP status code will be considered
    /// invalid.
    case successAndRedirect

    /// Validates only the status codes passed in the parameter. Any other HTTP status code will be considered
    /// invalid.
    case custom([Int])

    /// The list of HTTP status codes to validate.
    public var statusCodes: [Int] {
        switch self {
        case .success:
            return Array(200..<300)
        case .successAndRedirect:
            return Array(200..<400)
        case .custom(let codes):
            return codes
        case .none:
            return []
        }
    }

    /**
     Validates an HTTP status code.

     - Parameters:
        - statusCode: The HTTP status code to be validated.

     - Returns: `true` if the status code is valid based on the validation type defined by the enumeration case;
     `false` otherwise.
     */
    public func validate(statusCode: Int) -> Bool {
        self == .none || statusCodes.contains(statusCode)
    }
}
