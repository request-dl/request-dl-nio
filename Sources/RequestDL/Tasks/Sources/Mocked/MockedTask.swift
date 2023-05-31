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
public struct MockedTask<Element: Sendable>: RequestTask {

    // MARK: - Private properties

    private let payload: any MockedTaskPayload<Element>

    // MARK: - Inits

    /// Initializes a new instance of the `MockedTask` struct.
    ///
    /// - Parameters:
    ///   - version: The HTTP version of the response. Default is `.init(minor: 0, major: 2)`.
    ///   - status: The status of the response. Default is `.init(code: 200, reason: "Ok")`.
    ///   - isKeepAlive: A Boolean value indicating whether the connection should be kept alive.
    ///   Default is `false`.
    ///   - content: A closure that returns the content of the response.
    public init<Content: Property>(
        version: ResponseHead.Version = .init(minor: 0, major: 2),
        status: ResponseHead.Status = .init(code: 200, reason: "Ok"),
        isKeepAlive: Bool = false,
        @PropertyBuilder content: () -> Content
    ) where Element == AsyncResponse {
        self.payload = PropertyMockedTask(
            version: version,
            status: status,
            isKeepAlive: isKeepAlive,
            content: content()
        )
    }

    // MARK: - Public methods

    /**
     Executes the mocked task and returns a `TaskResult` encapsulating the mock data.

     - Returns: A `TaskResult` that encapsulates a Data object containing the mock data.
     - Throws: `MockedTaskFailedToCreateURLResponseError` if a URL response could not be created
     from the provided status code and headers.
     */
    public func result() async throws -> Element {
        try await payload.result()
    }
}

// MARK: - Deprecated

extension MockedTask {

    /**
     Initializes a new `MockedTask` with the given status code, headers and closure that returns the mocked data.

     - Parameters:
        - statusCode: The HTTP status code for the mocked response.
        - headers: The HTTP headers for the mocked response.
        - data: The closure that returns the mocked data.
    */
    @available(*, deprecated, renamed: "init()")
    public init(
        statusCode: StatusCode = 200,
        headers: [String: String]? = nil,
        data: () -> Data
    ) where Element == TaskResult<Data> {
        self.payload = LiteralMockedTaskPayload(
            statusCode: statusCode,
            headers: headers,
            data: data()
        )
    }
}
