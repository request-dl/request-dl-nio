/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A representation of an Authorization header.
public struct Authorization: Property {

    private let type: TokenType
    private let token: String

    /**
     Initializes a new instance of `Authorization` with the specified token type and token.

     - Parameters:
        - type: The type of token.
        - token: The token value.
     */
    public init<Token: StringProtocol>(_ type: TokenType, token: Token) {
        self.type = type
        self.token = String(token)
    }

    /**
     Initializes a new instance of `Authorization` with the specified token type and token.

     - Parameters:
        - type: The type of token.
        - token: The token value.
     */
    public init<Token: LosslessStringConvertible>(_ type: TokenType, token: Token) {
        self.type = type
        self.token = String(token)
    }

    /// Creates an `Authorization` instance for basic authentication using the given username and password.
    ///
    /// - Parameters:
    ///    - username: The username to be used for authentication.
    ///    - password: The password to be used for authentication.
    public init<Username: StringProtocol, Password: StringProtocol>(
        username: Username,
        password: Password
    ) {
        self.type = .basic
        self.token = {
            Data(String(username).utf8)
            + Data(":".utf8)
            + Data(String(password).utf8)
        }().base64EncodedString()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Authorization {

    /// Creates an `Authorization` instance for the given token type and token value.
    ///
    /// - Parameters:
    ///    - type: The type of the authorization token.
    ///    - token: The value of the authorization token.
    @available(*, deprecated, message: "Prefers token as String")
    public init(_ type: TokenType, token: Any) {
        self.type = type
        self.token = "\(token)"
    }
}

extension Authorization {

    private struct Node: PropertyNode {

        let type: TokenType
        let token: String

        func make(_ make: inout Make) async throws {
            make.request.headers.setValue(
                "\(type.rawValue) \(token)",
                forKey: "Authorization"
            )
        }
    }

    /// This method is used internally and should not be called directly.
        public static func _makeProperty(
        property: _GraphValue<Authorization>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(
            type: property.type,
            token: property.token
        ))
    }
}
