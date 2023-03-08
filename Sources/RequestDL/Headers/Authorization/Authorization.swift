//
//  Authorization.swift
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

extension Authorization: PrimitiveProperty {

    struct Object: NodeObject {
        let type: TokenType
        let token: Any

        init(_ type: TokenType, token: Any) {
            self.type = type
            self.token = token
        }

        func makeProperty(_ make: Make) {
            make.request.setValue("\(type.rawValue) \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    func makeObject() -> Object {
        .init(type, token: token)
    }
}
