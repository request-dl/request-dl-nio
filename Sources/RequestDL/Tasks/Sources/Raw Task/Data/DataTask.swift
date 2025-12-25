/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

/**
 Performs a request.

 You can use ``DataTask/result()`` function to receive the data result of the request.

 In the example below, a request is made to the Apple's website:

 ```swift
 func makeRequest() async throws {
     try await DataTask {
         BaseURL("apple.com")
     }
     .result()
 }
 ```

 > Note: The ``Property`` instance used by ``DataTask`` contains information about the request such as its URL, headers,
 body and etc.
 */
public struct DataTask<Content: Property>: RequestTask {

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
     Returns a task result that encapsulates the response data.

     - Returns: A ``TaskResult`` with `Data` as  its`payload`.

     - Throws: An error of type `Error` that indicates an issue with the request or response.
     */
    public func result() async throws -> TaskResult<Data> {
        try await task
            .collectData()
            .result()
    }
}
