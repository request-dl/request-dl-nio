//
//  Query.swift
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

public struct Query: Request {

    public typealias Body = Never

    let key: String
    let value: Any

    public init(_ value: Any, forKey key: String) {
        self.key = key
        self.value = "\(value)"
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension Query: PrimitiveRequest {

    class Object: NodeObject {

        let key: String
        let value: String

        init(_ value: Any, forKey key: String) {
            self.key = key
            self.value = "\(value)"
        }

        func makeRequest(_ configuration: RequestConfiguration) {
            configuration.request.url = configuration.request.url?.append([(key, value)])
        }
    }

    func makeObject() -> Object {
        Object(value, forKey: key)
    }
}

extension URL {

    func append(_ parameters: [(String, String)]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
        var queryItems = components?.queryItems ?? []

        parameters.forEach {
            queryItems.append(.init(name: $0, value: $1))
        }

        components?.queryItems = queryItems
        return components?.url ?? self
    }
}
