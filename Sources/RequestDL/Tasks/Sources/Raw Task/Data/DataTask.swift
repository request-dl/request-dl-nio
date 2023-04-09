/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that represents a data task request.

 Use `DataTask` to represent a request for a specific resource. After you've constructed your
 data task, you can use `result` function to receive the result of the request.

 In the example below, a request is made to the Apple's website:

 ```swift
 func makeRequest() {
     try await DataTask {
         BaseURL("apple.com")
     }
     .result()
 }
 ```
 - Note: `DataTask` is a generic type that accepts a type that conforms to `Property` as its
 parameter. `Property` protocol contains information about the request such as its URL, headers,
 body and etc.
 */
public struct DataTask<Content: Property>: Task {

    private let content: Content

    /**
     Initializes a `DataTask` instance.

     - Parameter content: The content of the request.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }
}

extension DataTask {

    /**
     Returns a task result that encapsulates the response data for a request.

     The `result` function is used to get the response data from a `DataTask` object. The function returns
     a `TaskResult<Data>` object that encapsulates the response data or any error that occurred during the
     request execution.

     - Returns: A `TaskResult<Data>` object that encapsulates the response data for a request.

     - Throws: An error of type `Error` that indicates an issue with the request or response.
     */
    public func result() async throws -> TaskResult<Data> {
        try await RawTask(content: content)
            .ignoresProgress()
            .result()
    }
}
