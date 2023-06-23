/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The ``RequestDL/Authorization/TokenType`` struct is used to define the authorization type of the request.

 ```swift
 let authorizationType: Authorization.TokenType = .bearer
 ```

 > Note: For a complete list of the available types, please see the corresponding static
 properties.

 > Important: If the authorization type is not included in the predefined static properties, use
 a string literal to initialize an instance of ``RequestDL/Authorization/TokenType``.

 The ``RequestDL/Authorization/TokenType`` struct conforms to the `ExpressibleByStringLiteral` protocol, allowing
 it to be initialized with a string literal.

 ```swift
 let customAuthorizationType: Authorization.TokenType = "Private"
 ```
 */
extension Authorization {

    public struct TokenType: Sendable, Hashable {

        // MARK: - Public static properties

        /// The `Bearer` authorization type
        public static let bearer: Authorization.TokenType = "Bearer"

        /// The `Basic` authorization type
        public static let basic: Authorization.TokenType = "Basic"

        // MARK: - Internal properties

        let rawValue: String

        // MARK: - Inits

        /**
         Initializes with a given string value.

         - Parameter rawValue: The string value of the authorization type.
         */
        public init<S: StringProtocol>(_ rawValue: S) {
            self.rawValue = String(rawValue)
        }
    }
}

// MARK: - ExpressibleByStringLiteral

extension Authorization.TokenType: ExpressibleByStringLiteral {

    /**
     Initializes a ``RequestDL/Authorization/TokenType`` instance using a string literal.

     - Parameter value: A string literal representing the authorization type.
     - Returns: An instance of ``RequestDL/Authorization/TokenType`` with the specified media type.

     > Note: Use this initializer to create a ``RequestDL/Authorization/TokenType`` instance from a string literal.
     */
    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

// MARK: - LosslessStringConvertible

extension Authorization.TokenType: LosslessStringConvertible {

    public var description: String {
        rawValue
    }
}
