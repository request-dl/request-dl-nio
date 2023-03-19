/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

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
    public func result() async throws -> AsyncResponse {
        let (session, request) = try await Resolver(content).make()
        return try session.request(request).response
    }
}

extension Modifiers {

    public struct Upload<Content: Task>: TaskModifier where Content.Element == AsyncResponse {

        public typealias Element = (ResponseHead, AsyncBytes)

        let progress: (Int) -> Void

        public func task(_ task: Content) async throws -> (ResponseHead, AsyncBytes) {
            let result = try await task.result()

            var body: (ResponseHead, AsyncBytes)?

            for try await part in result {
                switch part {
                case .upload(let bytes):
                    progress(bytes)
                case .download(let head, let bytes):
                    body = (head, bytes)
                }
            }

            guard let body else {
                fatalError()
            }

            return body
        }
    }
}

extension Task<AsyncResponse> {

    public func uploading(_ progress: @escaping (Int) -> Void) -> ModifiedTask<Modifiers.Upload<Self>> {
        modify(Modifiers.Upload(progress: progress))
    }
}

extension Modifiers {

    public struct Download<Content: Task>: TaskModifier where Content.Element == (ResponseHead, AsyncBytes) {

        public typealias Element = Data

        let contentLengthKey: String?
        let progress: (UInt8, Int?) -> Void

        public func task(_ task: Content) async throws -> Element {
            let (head, bytes) = try await task.result()

            let contentLenght = contentLengthKey
                .flatMap { head.headers.getValue(forKey: $0) }
                .flatMap(Int.init)

            var data = Data()

            for try await byte in bytes {
                data.append(byte)
            }

            return data
        }
    }
}

extension Task<(ResponseHead, AsyncBytes)> {

    public func download(
        _ contentLengthKey: String?,
        progress: @escaping (UInt8, Int?) -> Void
    ) -> ModifiedTask<Modifiers.Download<Self>> {
        modify(Modifiers.Download(
            contentLengthKey: contentLengthKey,
            progress: progress
        ))
    }
}
