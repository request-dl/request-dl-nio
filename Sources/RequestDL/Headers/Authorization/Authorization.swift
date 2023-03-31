/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A representation of an Authorization header.
public struct Authorization: Property {

    private let type: TokenType
    private let token: Any

    /// Creates an `Authorization` instance for the given token type and token value.
    ///
    /// - Parameters:
    ///    - type: The type of the authorization token.
    ///    - token: The value of the authorization token.
    public init(_ type: TokenType, token: Any) {
        self.type = type
        self.token = token
    }

    /// Creates an `Authorization` instance for basic authentication using the given username and password.
    ///
    /// - Parameters:
    ///    - username: The username to be used for authentication.
    ///    - password: The password to be used for authentication.
    public init(username: String, password: String) {
        self.type = .basic
        self.token = {
            Data("\(username):\(password)".utf8)
                .base64EncodedString()
        }()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Authorization {

    public static func _makeProperty(
        property: _GraphValue<Authorization>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(Headers.Node(
            "\(property.type.rawValue) \(property.token)",
            forKey: "Authorization"
        )))
    }
}
