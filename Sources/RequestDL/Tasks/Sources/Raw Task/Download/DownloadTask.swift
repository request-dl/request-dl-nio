/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that represents a download task request.

 Use `DownloadTask` to represent a async request for a specific resource. After you've constructed your
 download task, you can use `result` function to receive the async bytes result of the request.

 In the example below, a request is made to the Apple's website:

 ```swift
 func makeRequest() async throws {
     let result = try await DownloadTask {
         BaseURL("apple.com")
     }
     .result()

     var data = Data()

     for try await bytes in result.payload {
         data.append(bytes)
     }

     print("Received data: \(data)")
 }
 ```

 It's possible to control the length of bytes read by using the `ReadingMode` property.

 ```swift
 func makeRequest() async throws {
     let result = try await DownloadTask {
         BaseURL("apple.com")
         ReadingMode(separator: "\n")
     }
     .result()

     var table = [Data]()

     for try await line in result.payload {
         table.append(line)
     }

     print("Received table of contents: \(table)")
 }
 ```

 - Note: `DownloadTask` is a generic type that accepts a type that conforms to `Property` as its
 parameter. `Property` protocol contains information about the request such as its URL, headers,
 body and etc.
 */
@RequestActor
public struct DownloadTask<Content: Property>: Task {

    private let content: Content

    /**
     Initializes a `DownloadTask` instance.

     - Parameter content: The content of the request.
     */
    public init(@PropertyBuilder content: @RequestActor () -> Content) {
        self.content = content()
    }
}

extension DownloadTask {

    /**
     Returns a task result that encapsulates the async response bytes for a request.

     The `result` function is used to get the async response bytes from a `DownloadTask` object.
     The function returns a `TaskResult<AsyncBytes>` object that encapsulates the async response
     bytes or any error that occurred during the request execution.

     - Returns: A `TaskResult<AsyncBytes>` object that encapsulates the async response bytes
     for a request.

     - Throws: An error of type `Error` that indicates an issue with the request or response.
     */
    public func result() async throws -> TaskResult<AsyncBytes> {
        try await RawTask(content: content)
            .ignoresUploadProgress()
            .result()
    }
}
