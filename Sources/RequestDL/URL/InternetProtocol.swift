//
//  InternetProtocol.swift
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
 let customInternetProtocol: InternetProtocol = "htts"
 ```
 */
public struct InternetProtocol {

    let rawValue: String

    /**
     Initializes a `ContentType` instance with a given string value.

     - Parameter rawValue: The string value of the content type.
     */
    public init<S: StringProtocol>(_ rawValue: S) {
        self.rawValue = String(rawValue)
    }
}

extension InternetProtocol {

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
}

extension InternetProtocol: Equatable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

extension InternetProtocol: Hashable {

    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
}

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

extension InternetProtocol: CustomStringConvertible {

    public var description: String {
        rawValue
    }
}
