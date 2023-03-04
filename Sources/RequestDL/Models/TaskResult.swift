//
//  TaskResult.swift
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
A protocol that represents a primitive task result.

Conforming types must have a `response` property of type `URLResponse.
*/
public protocol TaskResultPrimitive {

    /// The URL response returned by the task.
    var response: URLResponse { get }
}

/**
A struct that represents the result of a network request.

A `TaskResult` consists of the HTTP response and the resulting data.

The type of the `data` parameter is generic, allowing you to define the type of data that will be returned. The
 `response` parameter represents the URL response of the network request.

This struct conforms to the `TaskResultPrimitive` protocol, which requires that it has a `response` property that
returns a `URLResponse` object.

You can initialize a `TaskResult` object by providing the response and data values using the `init(response:data:)`
 initializer.
*/
public struct TaskResult<Element>: TaskResultPrimitive {

    /// The URL response of the network request.
    public let response: URLResponse

    /// The resulting data of the network request.
    public let data: Element

    /**
     Initializes a `TaskResult` object with the given response and data.

     - Parameters:
        - response: The URL response of the network request.
        - data: The resulting data of the network request.
     */
    public init(response: URLResponse, data: Element) {
        self.response = response
        self.data = data
    }
}
