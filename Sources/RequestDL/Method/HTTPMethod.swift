//
//  HTTPMethod.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
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

/// HTTP methods for making requests.
public struct HTTPMethod {

    let rawValue: String

    /// Initializes an HTTP method with the specified raw value.
    /// - Parameter rawValue: The raw string value of the HTTP method.
    public init<S: StringProtocol>(_ rawValue: S) {
        self.rawValue = String(rawValue)
    }
}

extension HTTPMethod {

    /// HTTP GET method.
    public static let get: HTTPMethod = "GET"

    /// HTTP POST method.
    public static let post: HTTPMethod = "POST"

    /// HTTP PUT method.
    public static let put: HTTPMethod = "PUT"

    /// HTTP DELETE method.
    public static let delete: HTTPMethod = "DELETE"

    /// HTTP PATCH method.
    public static let patch: HTTPMethod = "PATCH"

    /// HTTP HEAD method.
    public static let head: HTTPMethod = "HEAD"

    /// HTTP OPTIONS method.
    public static let options: HTTPMethod = "OPTIONS"

    /// HTTP CONNECT method.
    public static let connect: HTTPMethod = "CONNECT"

    /// HTTP TRACE method.
    public static let trace: HTTPMethod = "TRACE"
}

extension HTTPMethod: Equatable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

extension HTTPMethod: Hashable {

    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
}

extension HTTPMethod: ExpressibleByStringLiteral {

    /// Initializes an HTTP method with the specified string literal value.
    /// - Parameter value: The string literal value of the HTTP method.
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}
