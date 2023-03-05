//
//  BaseURL.swift
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
 The BaseURL struct defines the base URL for a request. It provides the
 internet protocol and the host for the request.

 To create a BaseURL object, you need to provide the internet protocol
 and the string host. You can also set the internet protocol to HTTPS by
 default if you only provide the host.

 Example usage:

 ```swift
 import RequestDL

 struct AppleDeveloperBaseURL: Property {
     var body: some Property {
         BaseURL(.https, host: "developer.apple.com")
     }
 }

 ```

 Or you can set the host without specifying the protocol type:

 ```swift
 struct AppleDeveloperBaseURL: Property {
     var body: some Property {
         BaseURL("developer.apple.com")
     }
 }
 ```
 */
public struct BaseURL: Property {

    public typealias Body = Never

    let internetProtocol: InternetProtocol
    let host: String

    /**
     Creates a BaseURL by combining the internet protocol and the string host.

     - Parameters:
        - internetProtocol: The internet protocol chosen.
        - path: The string host only.

     Example usage:

     ```swift
     import RequestDL

     struct AppleDeveloperBaseURL: Property {

         var body: some Property {
             BaseURL(.https, host: "developer.apple.com")
         }
     }
     ```
     */
    public init(_ internetProtocol: InternetProtocol, host: String) {
        self.internetProtocol = internetProtocol
        self.host = host
    }

    /**
     Defines the base URL from the host with the default HTTPS protocol.

     - Parameters:
        - path: The string host only.

     Example usage:

     ```swift
     import RequestDL

     struct AppleDeveloperBaseURL: Property {

         var body: some Property {
             BaseURL("developer.apple.com")
         }
     }
     ```
     */
    public init(_ host: String) {
        self.init(.https, host: host)
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension BaseURL {

    fileprivate var absoluteString: String {
        if host.contains("://") {
            fatalError("Invalid host string: The protocol communication should not be included.")
        }

        guard let host = host.split(separator: "/").first else {
            fatalError("Unexpected format for host string: Could not extract the host.")
        }

        return "\(internetProtocol.rawValue)://\(host)"
    }
}

extension BaseURL: PrimitiveProperty {

    struct Object: NodeObject {

        let baseURL: URL

        init(_ baseURL: URL) {
            self.baseURL = baseURL
        }

        func makeProperty(_ configuration: MakeConfiguration) {}
    }

    func makeObject() -> Object {
        guard let baseURL = URL(string: absoluteString) else {
            fatalError("Failed to create URL from absolute string: \(absoluteString)")
        }

        return .init(baseURL)
    }
}
