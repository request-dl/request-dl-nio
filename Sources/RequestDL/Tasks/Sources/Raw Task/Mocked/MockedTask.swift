//
// See LICENSE for this package's licensing information.
//

/// A task that returns mocked data with a specific status code and headers, without performing any
/// real network call.
///
/// The `content` block describes the mocked response body the same way a real request describes its
/// outgoing one: a ``RequestDL/MockedBody`` there becomes the bytes streamed back as the response,
/// and its `Content-Type`/`Content-Length` are carried over automatically. Anything else declared in
/// `content` — ``RequestDL/Headers``, ``RequestDL/AcceptHeader``, ``RequestDL/Authorization``, etc. —
/// only shapes the resolved request used to compute the cache key and the response `url`; it is
/// **not** echoed into the mocked response headers. Use the `headers` parameter for that.
///
/// ```swift
/// MockedTask(
///     status: .init(code: 200, reason: "Ok"),
///     headers: ["Content-Type": "application/json"],
///     content: {
///         BaseURL("localhost")
///         MockedBody(
///             data: Data(
///                 """
///                 {
///                     "id": 1,
///                     "name": "John Doe",
///                     "email": "johndoe@example.com"
///                 }
///                 """.utf8
///             )
///         )
///     }
/// )
/// ```
///
/// Use `delay` to simulate network latency, and the ``MockedTask/init(throwing:delay:)`` initializer
/// to simulate a transport-level failure (a thrown error) instead of a response, for exercising a
/// consumer's error-handling paths without a live server.
///
/// > Note: If `content` configures a data cache and a matching entry already exists for the
/// resolved URL, that cached response is returned instead of the mocked one —
/// the mock only supplies what gets *written* to an empty cache, not what is served once one is
/// populated. A `cacheStrategy(.useCachedDataOnly)` is also remapped internally to
/// `.returnCachedDataElseLoad`, since a mock has no real cache to serve on a miss and the original
/// strategy would otherwise always fail.
public struct MockedTask: RequestTask {

    // MARK: - Private properties

    private let payload: any MockedTaskPayload<AsyncResponse>

    // MARK: - Inits

    ///
    /// Initializes with some informations about the response head and the ``Property`` content which will
    /// be the result of response.
    ///
    /// - Parameters:
    ///    - version: The HTTP version of the response. Default is `.init(minor: 0, major: 2)`.
    ///    - status: The status of the response. Default is `.init(code: 200, reason: "Ok")`.
    ///    - headers: Headers to attach to the mocked response, on top of the `Content-Type`/
    ///      `Content-Length` derived from the ``RequestDL/MockedBody`` declared in `content`. Takes
    ///      precedence when a name collides with one of those two.
    ///    - isKeepAlive: A Boolean value indicating whether the connection should be kept alive. Default is `false`.
    ///    - delay: How long to wait before delivering the mocked response. Default is `.zero`.
    ///    - content: A closure that returns the content of the response.
    ///
    public init<Content: Property>(
        version: ResponseHead.Version = .init(minor: 0, major: 2),
        status: ResponseHead.Status = .init(code: 200, reason: "Ok"),
        headers: HTTPHeaders = [:],
        isKeepAlive: Bool = false,
        delay: UnitTime = .zero,
        @PropertyBuilder content: () -> Content
    ) {
        self.payload = PropertyMockedTask(
            version: version,
            status: status,
            headers: headers,
            isKeepAlive: isKeepAlive,
            delay: delay,
            content: content()
        )
    }

    ///
    /// Initializes a mocked task that throws the given error instead of returning a response,
    /// simulating a transport-level failure (no connection, DNS failure, TLS error, ...).
    ///
    /// - Parameters:
    ///    - error: The error thrown by ``result()``.
    ///    - delay: How long to wait before throwing. Default is `.zero`.
    ///
    public init(
        throwing error: Error,
        delay: UnitTime = .zero
    ) {
        self.payload = ErrorMockedTask(
            error: error,
            delay: delay
        )
    }

    // MARK: - Public methods

    ///
    /// Executes the mocked task and returns the mocked ``RequestDL/AsyncResponse``.
    ///
    /// - Returns: An ``RequestDL/AsyncResponse`` containing the mock data.
    /// - Throws: Any `Error` that may occur in the process.
    ///
    public func result() async throws -> AsyncResponse {
        try await payload.result(environment)
    }
}
