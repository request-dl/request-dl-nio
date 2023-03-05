//
//  Headers.Origin.swift
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

extension Headers {

    /**
     A representation of the `Origin` header field in an HTTP message.

     The `Origin` header field indicates the origin of the request in terms of scheme, host, and port
     number. This header is mainly used in the context of CORS (Cross-Origin Resource Sharing)
     requests to ensure that a web application can only access resources from a different origin if the server
     explicitly allows it.

     Example usage:

     ```swift
     Headers.Origin("https://example.com")
     ```
     */
    public struct Origin: Property {

        private let value: Any

        /**
         Initializes a `Origin` property with the given `host` and `port`.

         - Parameters:
            - host: A `StringProtocol` representing the host.
            - port: A `StringProtocol` representing the port.
         */
        public init<Host, Port>(
            _ host: Host,
            port: Port
        ) where Host: StringProtocol, Port: StringProtocol {
            self.value = "\(host):\(port)"
        }

        /**
         Initializes an `Origin` header field with the given origin value.

         - Parameter host: A `StringProtocol` representing the host.
         */
        public init<S: StringProtocol>(_ origin: S) {
            self.value = origin
        }

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }
    }
}

extension Headers.Origin: PrimitiveProperty {

    func makeObject() -> Headers.Object {
        .init(value, forKey: "Origin")
    }
}
