/*
 See LICENSE for this package's licensing information.
*/

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

    public struct TokenType: Hashable {

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

extension Authorization.TokenType: ExpressibleByStringLiteral {

    /**
     Initializes a `Authorization.TokenType` instance using a string literal.

     - Parameter value: A string literal representing the authorization type.
     - Returns: An instance of `Authorization.TokenType` with the specified media type.

     - Note: Use this initializer to create a `Authorization.TokenType` instance from a string literal.
     */
    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

extension Authorization.TokenType: LosslessStringConvertible {

    public var description: String {
        rawValue
    }
}
