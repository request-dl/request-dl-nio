//
//  FormData.swift
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

/// A representation of data that can be sent in the body of an HTTP request using the `multipart/form-data` format.
public struct FormData: Property {

    public typealias Body = Never

    let data: Foundation.Data
    let fileName: String
    let key: String?
    let contentType: ContentType

    /// Creates a new `FormData` instance with the specified parameters.
    ///
    /// - Parameters:
    ///   - key: The key to associate with the data. Defaults to an empty string.
    ///   - name: The name to associate with the data.
    ///   - type: The content type of the data.
    ///   - data: The data to be sent.
    public init(
        key: String = "",
        name: String,
        type: ContentType,
        data: Foundation.Data
    ) {
        self.key = key.isEmpty ? nil : key
        self.fileName = name
        self.data = data
        self.contentType = type
    }

    /// Creates a new `FormData` instance by encoding a value as JSON data.
    ///
    /// - Parameters:
    ///   - key: The key to associate with the data. Defaults to an empty string.
    ///   - value: The value to be encoded as JSON data.
    ///   - encoder: The `JSONEncoder` to use for encoding the value.
    public init<T: Encodable>(
        key: String = "",
        _ value: T,
        encoder: JSONEncoder
    ) {
        self.key = key.isEmpty ? nil : key
        self.data = (try? encoder.encode(value)) ?? .init()
        self.fileName = "\(data.count).\(Int.random(in: 0...999))).json"
        self.contentType = .json
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }
}

extension FormData: PrimitiveProperty {

    func makeObject() -> FormObject {
        .init(.data(self))
    }
}
