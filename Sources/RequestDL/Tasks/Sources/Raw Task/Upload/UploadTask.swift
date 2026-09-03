//
// See LICENSE for this package's licensing information.
//

/// Performs a async request containing the upload and download steps.
///
/// You can use ``UploadTask/result()`` function to receive the async response of the request.
///
/// In the example below, a request is made to the Apple's website:
///
/// ```swift
/// func makeRequest() async throws {
///     let response = try await DownloadTask {
///         BaseURL("apple.com")
///     }
///     .result()
///
///     for try await step in response {
///         switch step {
///         case .upload(let step):
///             print("Uploaded \(step.chunkSize) bytes")
///         case .download(let step):
///             print("Received \(step.head) with async \(step.bytes)")
///         }
///     }
/// }
/// ```
///
/// It's possible to control the length of bytes read by using the ``ReadingMode`` property to has the same
/// behavior of ``DownloadTask``.
///
/// > Note: The ``Property`` instance used by ``UploadTask`` contains information about the request
/// such as its URL, headers, body and etc.
public struct UploadTask<Content: Property>: RequestTask {

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
    public func _result(environment: RequestEnvironmentValues) async throws -> AsyncResponse {
        try await task._result(environment: environment)
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
}
