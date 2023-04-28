/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that represents a upload task request.

 Use `UploadTask` to represent a async upload and download steps for a specific resource. After you've
 constructed your upload task, you can use `result` function to receive the async request.

 In the example below, a request is made to the Apple's website:

 ```swift
 func makeRequest() {
     let response = try await DownloadTask {
         BaseURL("apple.com")
     }
     .result()

     for try await step in response {
         switch step {
         case .upload(let part):
             print("Uploaded \(part) bytes")
         case .download(let head, let bytes):
             print("Received \(head) with async \(bytes)")
         }
     }
 }
 ```

 It's possible to control the length of bytes read by using the `ReadingMode` property to has the same
 behavior of `DownloadTask`.

 - Note: `UploadTask` is a generic type that accepts a type that conforms to `Property` as its
 parameter. `Property` protocol contains information about the request such as its URL, headers,
 body and etc.
 */
@RequestActor
public struct UploadTask<Content: Property>: Task {

    private let content: Content

    /**
     Initializes a `UploadTask` instance.

     - Parameter content: The content of the request.
     */
    public init(@PropertyBuilder content: @RequestActor () -> Content) {
        self.content = content()
    }
}

extension UploadTask {

    /**
     Returns a task result that encapsulates the asynchronous response for a request.

     The `result` function is used to retrieve the asynchronous response from an `UploadTask` object.
     The function returns an `AsyncResponse` object, which represents an asynchronous sequence of
     request steps that iterates from the upload step to the download step.

     - Returns: An `AsyncResponse` object that represents an asynchronous sequence of request
     steps.

     - Throws: An error of type `Error` that indicates an issue with the request or response.
     */
    public func result() async throws -> AsyncResponse {
        try await RawTask(content: content).result()
    }
}
