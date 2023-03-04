//
//  HTTPMethod.swift
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
 Defines the HTTP request method.

 Use `HTTPMethod` to specify the HTTP request method when creating requests.

 ```swift
 DataTask {
     BaseURL("ecommerce.com")
     Path("products")
     HTTPMethod(.get)
 }
 ```
 */
public struct HTTPMethod: Property {

    public typealias Body = Never

    let type: HTTPMethodType

    /**
     Initializes a `HTTPMethod` instance with the specified HTTP request method.

     - Parameter type: The type of HTTP request method to use.

     In the following example, a GET request is made to the Apple developers website:

     ```swift
     DataTask {
         BaseURL("developer.apple.com")
         Method(.get)
     }
     */
    public init(_ type: HTTPMethodType) {
        self.type = type
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }
}

extension HTTPMethod: PrimitiveProperty {

    struct Object: NodeObject {

        private let httpMethod: String

        init(_ httpMethod: String) {
            self.httpMethod = httpMethod
        }

        func makeProperty(_ configuration: MakeConfiguration) {
            configuration.request.httpMethod = httpMethod
        }
    }

    func makeObject() -> Object {
        .init(type.rawValue)
    }
}
