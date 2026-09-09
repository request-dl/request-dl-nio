//
// See LICENSE for this package's licensing information.
//

/// A task that mirrors a resolved request back as its own response, without performing any real
/// network call.
///
/// The `content` block is a request description just like any other task's — ``RequestDL/BaseURL``,
/// ``RequestDL/HeaderGroup``, ``RequestDL/AcceptHeader``, ``RequestDL/Authorization``,
/// ``RequestDL/Payload``, and so on. Resolving it produces the mocked response: every header the
/// request would carry (including `Content-Type`/`Content-Length` from ``RequestDL/Payload``) is
/// copied onto the response, and ``RequestDL/Payload``'s bytes become the response body. That makes
/// `MockedTask` a way to inspect exactly what a request would look like — URL, headers, encoded body
/// — by running it through the same result-processing pipeline (``RequestDL/RequestTask/collectData()-3viv5``,
/// modifiers, `.decode(_:)`, ...) a real task would use, without a live server.
///
/// ```swift
/// MockedTask(
///     status: .init(code: 200, reason: "Ok"),
///     content: {
///         BaseURL("localhost")
///         AcceptHeader(.json)
///         Payload(
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
/// Use `headers` to overlay something that isn't part of the request itself — a synthetic
/// response-only header, for instance. Use `delay` to simulate network latency, and the
/// ``MockedTask/init(throwing:delay:)`` initializer to simulate a transport-level failure (a thrown
/// error) instead of a response, for exercising a consumer's error-handling paths without a live
/// server.
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
    ///    - headers: Headers to overlay on top of the mocked response, which by default mirrors
    ///      every header the resolved request would carry. Takes precedence when a name collides
    ///      with one already on the resolved request.
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

    /// This method is used internally and should not be called directly.
    @_spi(Private)
    public func _result(environment: RequestEnvironmentValues) async throws -> AsyncResponse {
        try await payload.result(environment)
    }
}
