/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// HTTP methods for making requests.
public struct HTTPMethod: Sendable, Hashable {

    // MARK: - Public static properties

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

    // MARK: - Internal properties

    let rawValue: String

    // MARK: - Inits

    /**
     Initializes an HTTP method with the specified raw value.

     - Parameter rawValue: The raw string value of the HTTP method.
     */
    public init<S: StringProtocol>(_ rawValue: S) {
        self.rawValue = String(rawValue)
    }
}

// MARK: - ExpressibleByStringLiteral

extension HTTPMethod: ExpressibleByStringLiteral {
    
    /**
     Initializes an HTTP method with the specified string literal value.
     - Parameter value: The string literal value of the HTTP method.
     */
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

// MARK: - LosslessStringConvertible

extension HTTPMethod: LosslessStringConvertible {

    public var description: String {
        rawValue
    }
}
