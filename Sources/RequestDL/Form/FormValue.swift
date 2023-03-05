//
//  FormValue.swift
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

/// `FormValue` is a type of property that represents a single value in a multipart form-data request
///
/// It can be used to represent simple values like strings and numbers.
public struct FormValue: Property {

    public typealias Body = Never

    let key: String
    let value: Any

    /**
     Creates a new instance of `FormValue` to represent a value with a corresponding key in a form.

     The value parameter is the actual value to be sent, and key is the reference key used to identify
     the value when the form is submitted.

     - Parameters:
        - value: The value to be sent.
        - key: The key used to reference the value in the form.
     */
    public init(_ value: Any, forKey key: String) {
        self.key = key
        self.value = value
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }
}

extension FormValue: PrimitiveProperty {

    func makeObject() -> FormObject {
        .init(.value(self))
    }
}
