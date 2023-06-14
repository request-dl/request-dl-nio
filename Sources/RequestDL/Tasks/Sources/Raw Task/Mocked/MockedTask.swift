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

    // MARK: - Public properties

    @_spi(Private)
    public var environment = TaskEnvironmentValues()

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
        try await payload.result(environment)
    }
}
