/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

/**
 A task that returns mocked data with a specific status code and headers.

 Usage:

 ```swift
 MockedTask(
     statusCode: 200,
     headers: ["Content-Type": "application/json"],
     data: {
         Data(
             """
             {
                 "id": 1,
                 "name": "John Doe",
                 "email": "johndoe@example.com"
             }
             """.utf8
         )
     }
 )
 ```
*/
public struct MockedTask: RequestTask {

    // MARK: - Private properties

    private let statusCode: StatusCode
    private let headers: [String: String]?
    private let data: Data

    // MARK: - Inits

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

    // MARK: - Public methods

    /**
     Executes the mocked task and returns a `TaskResult` encapsulating the mock data.

     - Returns: A `TaskResult` that encapsulates a Data object containing the mock data.
     - Throws: `MockedTaskFailedToCreateURLResponseError` if a URL response could not be created
     from the provided status code and headers.
     */
    public func result() async throws -> TaskResult<Data> {
        .init(
            head: ResponseHead(
                url: nil,
                status: .init(
                    code: statusCode.rawValue,
                    reason: "Mock status"
                ),
                version: .init(minor: 1, major: 2),
                headers: .init(Array(headers ?? [:])),
                isKeepAlive: false
            ),
            payload: data
        )
    }
}
