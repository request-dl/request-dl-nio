/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A task that receives the `Content` request and returns bytes data.

 This task represents a type that can handle requests and return the result in bytes.

 Usage:

 ```swift
 func makeRequest() {
     try await BytesTask {
         BaseURL("google.com")
     }
     .result()
 }
 ```

 - Note: Only available on iOS 15.0+, tvOS 15.0+, watchOS 15.0+, macOS 12.0+.
*/
@available(iOS 15, tvOS 15, watchOS 15, macOS 12, *)
@available(*, deprecated, renamed: "DataTask")
public struct BytesTask<Content: Property>: Task {

    private let content: Content

    /**
     Initializes a new `BytesTask` object.

     - Parameters:
        - content: The request builder block that returns the `Content` request.

     Usage:

     ```swift
     func makeRequest() {
         try await BytesTask {
             BaseURL("google.com")
         }
         .result()
     }
     ```
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }
}

@available(iOS 15, tvOS 15, watchOS 15, macOS 12, *)
@available(*, deprecated, renamed: "DataTask")
extension BytesTask {

    /**
    Returns the result of a `Task` execution with a response of bytes delivered asynchronously.

    - Returns: A `TaskResult` with a payload of `URLSession.AsyncBytes`.

    - Throws: Any error encountered during the execution of the task.
    */
    public func result() async throws -> TaskResult<URLSession.AsyncBytes> {
        let delegate = DelegateProxy()
        let (session, request) = try await Resolve(content).build(delegate)

        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.bytes(for: request, delegate: delegate)
        return .init(response: response, data: data)
    }
}
