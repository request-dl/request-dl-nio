/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `URLScheme` struct is a data type that represents the protocol type used in a request

 Usage:

 ```swift
 let scheme: URLScheme = .https
 ```

 - Note: For a complete list of the available types, please see the corresponding static
 properties.

 - Important: If the internet protocol type is not included in the predefined static properties, use
 a string literal to initialize an instance of URLScheme.

 The URLScheme struct conforms to the `ExpressibleByStringLiteral` protocol, allowing
 it to be initialized with a string literal, like so:

 ```swift
 let customScheme: URLScheme = "www"
 ```
 */
public struct URLScheme: Sendable, Hashable {

    // MARK: - Public static methods

    /// The HTTP protocol.
    public static let http: URLScheme = "http"

    /// The HTTPS protocol.
    public static let https: URLScheme = "https"

    /// The FTP protocol.
    public static let ftp: URLScheme = "ftp"

    /// The SMTP protocol.
    public static let smtp: URLScheme = "smtp"

    /// The IMAP protocol.
    public static let imap: URLScheme = "imap"

    /// The POP protocol.
    public static let pop: URLScheme = "pop"

    /// The DNS protocol.
    public static let dns: URLScheme = "dns"

    /// The SSH protocol.
    public static let ssh: URLScheme = "ssh"

    /// The Telnet protocol.
    public static let telnet: URLScheme = "telnet"

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

extension URLScheme: ExpressibleByStringLiteral {

    /**
     Initializes a `URLScheme` instance using a string literal.

     - Parameter value: A string literal representing the internet protocol type.
     - Returns: An instance of `URLScheme` with the specified internet protocol type.

     - Note: Use this initializer to create a `URLScheme` instance from a string literal.
     */
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

// MARK: - LosslessStringConvertible

extension URLScheme: LosslessStringConvertible {

    public var description: String {
        rawValue
    }
}

// MARK: - Deprecated

@available(*, deprecated, renamed: "URLScheme")
public typealias InternetProtocol = URLScheme
