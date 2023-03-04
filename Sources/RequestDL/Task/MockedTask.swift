//
//  MockedTask.swift
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
 A task that returns mocked data with a specific status code and headers.

 Usage:

 ```swift
 MockedTask(
     statusCode: 200,
     headers: ["Content-Type": "application/json"],
     data: {
         """
         {
             "id": 1,
             "name": "John Doe",
             "email": "johndoe@example.com"
         }
         """.data(using: .utf8)!
     }
 )
 ```
*/
public struct MockedTask: Task {

    private let statusCode: Int
    private let headers: [String: String]?
    private let data: Data

    /**
     Initializes a new `MockedTask` with the given status code, headers and closure that returns the mocked data.

     - Parameters:
        - statusCode: The HTTP status code for the mocked response.
        - headers: The HTTP headers for the mocked response.
        - data: The closure that returns the mocked data.
    */
    public init(
        statusCode: Int = 200,
        headers: [String: String]? = nil,
        data: () -> Data
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data()
    }
}

extension MockedTask {

    /**
     Executes the mocked task and returns a `TaskResult` encapsulating the mock data.

     - Returns: A `TaskResult` that encapsulates a Data object containing the mock data.
     - Throws: `MockedTaskFailedToCreateURLResponseError` if a URL response could not be created
     from the provided status code and headers.
     */
    public func response() async throws -> TaskResult<Data> {
        guard let response = HTTPURLResponse(
            url: FileManager.default.temporaryDirectory,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        ) else { throw FailedToCreateURLResponseError() }

        return .init(response: response, data: data)
    }
}

public struct FailedToCreateURLResponseError: LocalizedError {

    init() {}

    public var errorDescription: String? {
        "Failed to create URL response for mocked task"
    }
}
