//
// See LICENSE for this package's licensing information.
//

/// Performs a download request.
///
/// You can use ``DownloadTask/result()`` function to receive the async bytes result of the request.
///
/// In the example below, a request is made to the Apple's website:
///
/// ```swift
/// func makeRequest() async throws {
///     let result = try await DownloadTask {
///         BaseURL("apple.com")
///     }
///     .result()
///
///     var data = Data()
///
///     for try await bytes in result.payload {
///         data.append(bytes)
///     }
///
///     print("Received data: \(data)")
/// }
/// ```
///
/// It's possible to control the length of bytes read by using the ``ReadingMode`` property.
///
/// ```swift
/// func makeRequest() async throws {
///     let result = try await DownloadTask {
///         BaseURL("apple.com")
///         ReadingMode(separator: "\n")
///     }
///     .result()
///
///     var table = [Data]()
///
///     for try await line in result.payload {
///         table.append(line)
///     }
///
///     print("Received table of contents: \(table)")
/// }
/// ```
///
/// > Note: The ``Property`` instance used by ``DownloadTask`` contains information about the request
/// such as its URL, headers, body and etc.
public struct DownloadTask<Content: Property>: RequestTask {

    // MARK: - Private properties

    private let task: RawTask<Content>

    // MARK: - Inits

    ///
    /// Initializes with a ``Property`` as its content.
    ///
    /// - Parameter content: The content of the request.
    ///
    public init(@PropertyBuilder content: () -> Content) {
        self.task = RawTask(content: content())
    }

    // MARK: - Public methods

    /// This method is used internally and should not be called directly.
    @_spi(Private)
    public func _result(environment: RequestEnvironmentValues) async throws -> TaskResult<AsyncBytes> {
        try await task
            .collectBytes()
            ._result(environment: environment)
    }

    ///
    /// Resolves this task's request and hands it to `descriptor`, without performing it.
    ///
    /// - Parameter descriptor: The ``TaskDescriptor`` that produces the description.
    /// - Returns: The descriptor's output — a curl command line for ``CURLTaskDescriptor/cURL``.
    /// - Throws: An error thrown while resolving the request, or by the descriptor itself.
    ///
    public func description<Descriptor: TaskDescriptor>(_ descriptor: Descriptor) async throws -> Descriptor.Output {
        try await task.description(descriptor)
    }

    ///
    /// Resolves this task's request through `descriptor`, hands the output to `onDescribe`, then
    /// performs the request for real -- two separate passes, exactly as calling
    /// ``description(_:)`` followed by ``result()`` would.
    ///
    /// - Parameters:
    ///   - descriptor: The ``TaskDescriptor`` that produces the description.
    ///   - enabled: When `false`, skips the descriptor pass entirely (`onDescribe` is not
    ///   called) and goes straight to performing the request -- useful to disable the extra
    ///   resolve pass in production without removing the call site.
    ///   - onDescribe: Called with the descriptor's output once it's ready.
    /// - Returns: This task's actual result, exactly as ``result()`` would produce it.
    /// - Throws: An error thrown while producing the description, or while performing the
    /// request itself.
    ///
    public func description<Descriptor: TaskDescriptor>(
        _ descriptor: Descriptor,
        enabled: Bool = true,
        onDescribe: @escaping @Sendable (Descriptor.Output) -> Void
    ) async throws -> Element {
        if enabled {
            onDescribe(try await description(descriptor))
        }

        return try await result()
    }
}
