//
//  HTTPBody.swift
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
 A representation of the HTTP body data in a request.

 A `HTTPBody` can be initialized with various types of data: a dictionary, an encodable value, a string, or a raw
 `Data`.

 The body data is used in HTTP requests with the purpose of carrying information. When making a HTTP request,
 the request body is used to send information to the server. The server reads the information and acts upon it, for
 example, by returning a specific response or by modifying its behavior.

 To create a `HTTPBody`, initialize an instance with a dictionary, an encodable value, a string, or a raw `Data.

 Example:

 ```swift
 let bodyDict = ["name": "John", "age": 28]

 DataTask {
     BaseURL("apple.com")
     HTTPMethod(.post)
     HTTPBody(bodyDict)
 }
 ```
 */
public struct HTTPBody<Provider: BodyProvider>: Property {

    public typealias Body = Never

    private let provider: Provider

    /**
     Initializes a `HTTPBody` with a dictionary.

     - Parameters:
        - dictionary: A dictionary to be serialized.
        - options: Options for serializing the dictionary.
     */
    public init(
        _ dictionary: [String: Any],
        options: JSONSerialization.WritingOptions = .prettyPrinted
    ) where Provider == _DictionaryBody {
        provider = _DictionaryBody(dictionary, options: options)
    }

    /**
     Initializes a `HTTPBody` with an encodable value.

     - Parameters:
        - value: An encodable value to be serialized.
        - encoder: An encoder to use for the serialization.
     */
    public init<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = .init()
    ) where Provider == _EncodableBody<T> {
        provider = _EncodableBody(value, encoder: encoder)
    }

    /**
     Initializes a `HTTPBody` with a string.

     - Parameters:
        - string: A string to be used as the body data.
        - encoding: The encoding to use when converting the string to data.
     */
    public init(
        _ string: String,
        using encoding: String.Encoding = .utf8
    ) where Provider == _StringBody {
        provider = _StringBody(string, using: encoding)
    }

    /**
     Initializes a `HTTPBody` with raw `Data`.

     - Parameters:
        - data: The raw data to be used as the body.
     */
    public init(_ data: Data) where Provider == _DataBody {
        provider = _DataBody(data)
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }
}

extension HTTPBody: PrimitiveProperty {

    struct Object: NodeObject {

        private let provider: Provider

        init(_ provider: Provider) {
            self.provider = provider
        }

        func makeProperty(_ configuration: MakeConfiguration) {
            configuration.request.httpBody = provider.data
        }
    }

    func makeObject() -> Object {
        .init(provider)
    }
}
