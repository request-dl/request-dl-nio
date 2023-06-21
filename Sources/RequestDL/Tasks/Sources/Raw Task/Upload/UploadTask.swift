/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Performs a async request containing the upload and download steps.

 You can use ``UploadTask/result()`` function to receive the async response of the request.

 In the example below, a request is made to the Apple's website:

 ```swift
 func makeRequest() async throws {
     let response = try await DownloadTask {
         BaseURL("apple.com")
     }
     .result()

     for try await step in response {
         switch step {
         case .upload(let step):
             print("Uploaded \(step.chunkSize) bytes")
         case .download(let step):
             print("Received \(step.head) with async \(step.bytes)")
         }
     }
 }
 ```

 It's possible to control the length of bytes read by using the ``ReadingMode`` property to has the same
 behavior of ``DownloadTask``.

 > Note: The ``Property`` instance used by ``UploadTask`` contains information about the request such as its URL, headers,
 body and etc.
 */
public struct UploadTask<Content: Property>: RequestTask {

    // MARK: - Public properties

    @_spi(Private)
    public var environment: TaskEnvironmentValues {
        get { task.environment }
        set { task.environment = newValue }
    }

    // MARK: - Private properties

    private var task: RawTask<Content>

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
     Returns the asynchronous response for a request.

     - Returns: An ``AsyncResponse`` sequence of request upload and download steps.

     - Throws: An error of type `Error` that indicates an issue with the request or response.
     */
    public func result() async throws -> AsyncResponse {
        try await task.result()
    }
}
