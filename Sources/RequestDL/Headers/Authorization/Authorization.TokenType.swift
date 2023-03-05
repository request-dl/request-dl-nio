//
//  Authorization.TokenType.swift
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

/**
 The Authorization.TokenType struct is used to define the authorization type of the request.

 Usage:

 ```swift
 let authorizationType: Authorization.TokenType = .bearer
 ```

 - Note: For a complete list of the available types, please see the corresponding static
 properties.

 - Important: If the authorization type is not included in the predefined static properties, use
 a string literal to initialize an instance of Authorization.TokenType.

 The Authorization.TokenType struct conforms to the `ExpressibleByStringLiteral` protocol, allowing
 it to be initialized with a string literal, like so:

 ```swift
 let customAuthorizationType: Authorization.TokenType = "Private"
 ```
 */
extension Authorization {

    public struct TokenType {

        let rawValue: String

        /**
         Initializes a `Authorization.TokenType` instance with a given string value.

         - Parameter rawValue: The string value of the authorization type.
         */
        public init<S: StringProtocol>(_ rawValue: S) {
            self.rawValue = String(rawValue)
        }
    }
}

extension Authorization.TokenType {

    /// The `Bearer` authorization type
    public static let bearer: Authorization.TokenType = "Bearer"

    /// The `Basic` authorization type
    public static let basic: Authorization.TokenType = "Basic"
}

extension Authorization.TokenType: Equatable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

extension Authorization.TokenType: Hashable {

    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
}

extension Authorization.TokenType: ExpressibleByStringLiteral {

    /**
     Initializes a `Authorization.TokenType` instance using a string literal.

     - Parameter value: A string literal representing the authorization type.
     - Returns: An instance of `Authorization.TokenType` with the specified media type.

     - Note: Use this initializer to create a `Authorization.TokenType` instance from a string literal.
     */
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

extension Authorization.TokenType: CustomStringConvertible {

    public var description: String {
        rawValue
    }
}
