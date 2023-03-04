//
//  BytesTask.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

/**
 A task that receives the `Content` request and returns bytes data.

 This task represents a type that can handle requests and return the response in bytes.

 Usage:

 ```swift
 func makeRequest() {
     try await BytesTask {
         BaseURL("google.com")
     }
     .response()
 }
 ```

 - Note: Only available on iOS 15.0+, tvOS 15.0+, watchOS 15.0+, macOS 12.0+.
*/
@available(iOS 15, tvOS 15, watchOS 15, macOS 12, *)
public struct BytesTask<Content: Request>: Task {

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
         .response()
     }
     ```
     */
    public init(@RequestBuilder content: () -> Content) {
        self.content = content()
    }
}

@available(iOS 15, tvOS 15, watchOS 15, macOS 12, *)
extension BytesTask {

    /**
    Returns the result of a `Task` execution with a response of bytes delivered asynchronously.

    - Returns: A `TaskResult` with a payload of `URLSession.AsyncBytes`.

    - Throws: Any error encountered during the execution of the task.
    */
    public func response() async throws -> TaskResult<URLSession.AsyncBytes> {
        let delegate = DelegateProxy()
        let (session, request) = await Resolver(content).make(delegate)

        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.bytes(for: request, delegate: delegate)
        return .init(response: response, data: data)
    }
}
