/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
A protocol that represents a primitive task result.

Conforming types must have a `response` property of type `URLResponse.
*/
public protocol TaskResultPrimitive {

    /// The URL response returned by the task.
    var status: UInt { get }

    var version: (minor: Int, major: Int) { get }

    var headers: [String: String] { get }
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
    public let status: UInt

    public let version: (minor: Int, major: Int)

    public let headers: [String: String]

    /// The resulting data of the network request.
    public let payload: Element

    /**
     Initializes a `TaskResult` object with the given response and data.

     - Parameters:
        - response: The URL response of the network request.
        - data: The resulting data of the network request.
     */
    public init(
        status: UInt,
        version: (minor: Int, major: Int),
        headers: [String: String],
        payload: Element
    ) {
        self.status = status
        self.version = version
        self.headers = headers
        self.payload = payload
    }
}
