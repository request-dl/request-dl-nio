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

public enum StatusCodeValidation: Equatable {

    /// No validation.
    case none

    /// Validate success codes (only 2xx).
    case success

    /// Validate success codes and redirection codes (only 2xx and 3xx).
    case successAndRedirect

    /// Validate only the given status codes.
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

    public func validate(statusCode: Int) -> Bool {
        self == .none || statusCodes.contains(statusCode)
    }
}
