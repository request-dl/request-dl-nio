/*
 See LICENSE for this package's licensing information.
*/

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

    private let statusCode: StatusCode
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
        statusCode: StatusCode = 200,
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
    public func result() async throws -> TaskResult<Data> {
        .init(
            head: ResponseHead(
                status: .init(
                    code: statusCode.rawValue,
                    reason: "Mock status"
                ),
                version: .init(minor: 1, major: 2),
                headers: .init(headers ?? [:]),
                isKeepAlive: false
            ),
            payload: data
        )
    }
}
