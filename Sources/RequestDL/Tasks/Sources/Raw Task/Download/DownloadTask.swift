/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Performs a download request.

 You can use ``DownloadTask/result()`` function to receive the async bytes result of the request.

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

 It's possible to control the length of bytes read by using the ``ReadingMode`` property.

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

 > Note: The ``Property`` instance used by ``DownloadTask`` contains information about the request
 such as its URL, headers, body and etc.
 */
public struct DownloadTask<Content: Property>: RequestTask {

    // MARK: - Private properties

    private let task: RawTask<Content>

    // MARK: - Inits

    /**
     Initializes with a ``Property`` as its content.

     - Parameter content: The content of the request.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.task = RawTask(content: content())
    }

    // MARK: - Public methods

    /**
     Returns a task result that encapsulates the response async bytes.

     - Returns: A ``TaskResult`` with ``AsyncBytes`` as its `payload`.
     - Throws: An error of type `Error` that indicates an issue with the request or response.
     */
    public func result() async throws -> TaskResult<AsyncBytes> {
        try await task
            .collectBytes()
            .result()
    }
}
