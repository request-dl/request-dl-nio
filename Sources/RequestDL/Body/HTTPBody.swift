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

public struct HTTPBody<Provider: BodyProvider>: Request {

    public typealias Body = Never

    private let provider: Provider

    public init(
        _ dictionary: [String: Any],
        options: JSONSerialization.WritingOptions = .prettyPrinted
    ) where Provider == _DictionaryBody {
        provider = _DictionaryBody(dictionary, options: options)
    }

    public init<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = .init()
    ) where Provider == _EncodableBody<T> {
        provider = _EncodableBody(value, encoder: encoder)
    }

    public init(
        _ string: String,
        using encoding: String.Encoding = .utf8
    ) where Provider == _StringBody {
        provider = _StringBody(string, using: encoding)
    }

    public init(_ data: Data) where Provider == _DataBody {
        provider = _DataBody(data)
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension HTTPBody: PrimitiveRequest {

    struct Object: NodeObject {

        private let provider: Provider

        init(_ provider: Provider) {
            self.provider = provider
        }

        func makeRequest(_ configuration: RequestConfiguration) {
            configuration.request.httpBody = provider.data
        }
    }

    func makeObject() -> Object {
        .init(provider)
    }
}
