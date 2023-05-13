/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `InternetProtocol` struct is a data type that represents the protocol type used in a request

 Usage:

 ```swift
 let internetProtocol: InternetProtocol = .https
 ```

 - Note: For a complete list of the available types, please see the corresponding static
 properties.

 - Important: If the internet protocol type is not included in the predefined static properties, use
 a string literal to initialize an instance of InternetProtocol.

 The InternetProtocol struct conforms to the `ExpressibleByStringLiteral` protocol, allowing
 it to be initialized with a string literal, like so:

 ```swift
 let customInternetProtocol: InternetProtocol = "www"
 ```
 */
public struct InternetProtocol: Sendable, Hashable {

    // MARK: - Public static methods

    /// The HTTP protocol.
    public static let http: InternetProtocol = "http"

    /// The HTTPS protocol.
    public static let https: InternetProtocol = "https"

    /// The FTP protocol.
    public static let ftp: InternetProtocol = "ftp"

    /// The SMTP protocol.
    public static let smtp: InternetProtocol = "smtp"

    /// The IMAP protocol.
    public static let imap: InternetProtocol = "imap"

    /// The POP protocol.
    public static let pop: InternetProtocol = "pop"

    /// The DNS protocol.
    public static let dns: InternetProtocol = "dns"

    /// The SSH protocol.
    public static let ssh: InternetProtocol = "ssh"

    /// The Telnet protocol.
    public static let telnet: InternetProtocol = "telnet"

    // MARK: - Internal properties

    let rawValue: String

    // MARK: - Inits

    /**
     Initializes a `ContentType` instance with a given string value.

     - Parameter rawValue: The string value of the content type.
     */
    public init<S: StringProtocol>(_ rawValue: S) {
        self.rawValue = String(rawValue)
    }
}

// MARK: - ExpressibleByStringLiteral

extension InternetProtocol: ExpressibleByStringLiteral {

    /**
     Initializes a `InternetProtocol` instance using a string literal.

     - Parameter value: A string literal representing the internet protocol type.
     - Returns: An instance of `InternetProtocol` with the specified internet protocol type.

     - Note: Use this initializer to create a `InternetProtocol` instance from a string literal.
     */
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

// MARK: - LosslessStringConvertible

extension InternetProtocol: LosslessStringConvertible {

    public var description: String {
        rawValue
    }
}
