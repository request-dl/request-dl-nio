//
//  BaseURL.swift
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

/**
 The BaseURL is the only way to specify the request's base URL.

 ```swift
 struct AppleDeveloperBaseURL: Request {

     var body: some Request {
         BaseURL(.https, host: "developer.apple.com")
     }
 }
 ```
 */
public struct BaseURL: Request {

    public typealias Body = Never

    let `protocol`: Protocol
    let host: String

    /**
     Creates a BaseURL by combining the communication protocol and the string host.

     - Parameters:
        - protocol: The communication protocol chosen;
        - path: The string host only.

     See example below:

     ```swift
     import RequestDL

     struct AppleDeveloperBaseURL: Request {

         var body: some Request {
             BaseURL(.https, host: "developer.apple.com")
         }
     }
     ```
     */
    public init(_ `protocol`: Protocol, host: String) {
        self.protocol = `protocol`
        self.host = host
    }

    /**
     Defines the base URL from host with default https protocol.

     - Parameters:
        - path: The String host.

     Use `BaseURL(_:)` when you want to set the host without
     specifying the protocol type, which it'll be the HTTPS. But don't
     try to force the http:// by using it inside the string. It may cause
     a wrong request URL.

     As the example below:

     ```swift
     struct AppleDeveloperBaseURL: Request {

         var body: some Request {
             BaseURL("developer.apple.com")
         }
     }
     ```
     */
    public init(_ host: String) {
        self.init(.https, host: host)
    }

    public var body: Body {
        Never.bodyException()
    }
}

extension BaseURL {

    fileprivate var absoluteString: String {
        if host.contains("://") {
            fatalError("Remove the protocol communication inside the host string")
        }

        guard let host = host.split(separator: "/").first else {
            fatalError("Found unexpected format for host string specified")
        }

        return "\(`protocol`.rawValue)://\(host)"
    }
}


extension BaseURL: PrimitiveRequest {

    struct Object: NodeObject {

        let baseURL: URL

        init(_ baseURL: URL) {
            self.baseURL = baseURL
        }

        func makeRequest(_ configuration: RequestConfiguration) {}
    }

    func makeObject() -> Object {
        guard let baseURL = URL(string: absoluteString) else {
            fatalError()
        }

        return .init(baseURL)
    }
}
