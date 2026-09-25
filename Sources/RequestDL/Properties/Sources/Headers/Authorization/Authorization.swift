//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A representation of an Authorization header.
public struct Authorization: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let type: TokenType
    private let token: String

    // MARK: - Inits

    ///
    /// Initializes with the specified token type and token.
    ///
    /// - Parameters:
    ///    - type: The type of token.
    ///    - token: The token value.
    ///
    public init<Token: StringProtocol>(_ type: TokenType, token: Token) {
        self.type = type
        self.token = String(token)
    }

    ///
    /// Initializes with the specified token type and token.
    ///
    /// - Parameters:
    ///    - type: The type of token.
    ///    - token: The token value.
    ///
    public init<Token: LosslessStringConvertible>(_ type: TokenType, token: Token) {
        self.type = type
        self.token = String(token)
    }

    ///
    /// Creates an `Authorization` instance for basic authentication using the given username and password.
    ///
    /// - Parameters:
    ///    - username: The username to be used for authentication.
    ///    - password: The password to be used for authentication.
    ///
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

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Authorization>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        // A plain `HeaderNode`, not a private node of its own: `HeaderGroup` (and `Form`'s
        // per-part headers) collect their content by searching for `HeaderNode`, so a private
        // node was silently dropped there and the request went out unauthenticated.
        // `HeaderNode` already treats `Authorization` as single-valued, so this still replaces
        // any earlier value exactly like the old direct `headers.set(...)` did.
        return .leaf(
            HeaderNode(
                key: "Authorization",
                value: "\(property.type.rawValue) \(property.token)",
                strategy: .setting,
                separator: nil
            )
        )
    }
}
