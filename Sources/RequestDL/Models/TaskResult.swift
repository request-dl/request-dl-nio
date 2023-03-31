/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
A protocol that represents a primitive task result.

Conforming types must have a `response` property of type `URLResponse.
*/
public protocol TaskResultPrimitive {

    var head: ResponseHead { get }

    /// The URL response returned by the task.
    @available(*, deprecated, renamed: "head")
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

    public let head: ResponseHead

    public let payload: Element

    private let _response: URLResponse?

    /// The URL response of the network request.
    @available(*, deprecated, renamed: "head")
    public var response: URLResponse {
        guard let _response else {
            fatalError("TaskResult was init with head")
        }

        return _response
    }

    /// The resulting data of the network request.
    @available(*, deprecated, renamed: "payload")
    public var data: Element {
        payload
    }

    public init(
        head: ResponseHead,
        payload: Element
    ) {
        self.head = head
        self.payload = payload
        self._response = nil
    }

    /**
     Initializes a `TaskResult` object with the given response and data.

     - Parameters:
        - response: The URL response of the network request.
        - data: The resulting data of the network request.
     */
    @available(*, deprecated, renamed: "head")
    public init(response: URLResponse, data: Element) {
        self.head = .init(response)
        self._response = response
        self.payload = data
    }
}
