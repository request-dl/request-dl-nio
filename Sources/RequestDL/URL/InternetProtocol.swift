//
//  InternetProtocol.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
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

public struct InternetProtocol {

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension InternetProtocol {

    public static var http: InternetProtocol {
        .init(rawValue: "http")
    }

    public static var https: InternetProtocol {
        .init(rawValue: "https")
    }

    public static var ftp: InternetProtocol {
        .init(rawValue: "ftp")
    }

    public static var smtp: InternetProtocol {
        .init(rawValue: "smtp")
    }

    public static var imap: InternetProtocol {
        .init(rawValue: "imap")
    }

    public static var pop: InternetProtocol {
        .init(rawValue: "pop")
    }

    public static var dns: InternetProtocol {
        .init(rawValue: "dns")
    }

    public static var ssh: InternetProtocol {
        .init(rawValue: "ssh")
    }

    public static var telnet: InternetProtocol {
        .init(rawValue: "telnet")
    }
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

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}
