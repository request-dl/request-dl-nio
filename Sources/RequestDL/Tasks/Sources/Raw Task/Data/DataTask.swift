//
// See LICENSE for this package's licensing information.
//

import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Performs a request.
///
/// You can use ``DataTask/result()`` function to receive the data result of the request.
///
/// In the example below, a request is made to the Apple's website:
///
/// ```swift
/// func makeRequest() async throws {
///     try await DataTask {
///         BaseURL("apple.com")
///     }
///     .result()
/// }
/// ```
///
/// > Note: The ``Property`` instance used by ``DataTask`` contains information about the request such as its URL, headers,
/// body and etc.
///
/// ## A server that answers before the body is all sent
///
/// A server may answer while the body is still being sent (`413`, `408`, `401`, even a `2xx`)
/// and close the connection. Under `.nio` and `.nioTransportServices` that answer is what the
/// task returns, with the status the server gave, and the task does not throw: the connection
/// closing after a complete response is not an error. Nothing in the result says the body did
/// not go out whole, so a `2xx` is not a confirmation that the server received all of it. When
/// that matters (a large upload that the server may cut short), compare what the upload
/// reported (``RequestMonitor``, or the ``UploadStep`` of ``UploadTask``) with the size of the
/// body: the upload reached its total only if the whole body was sent.
///
/// The same goes for a server that answers early with a `2xx` and does *not* close the
/// connection, which goes on waiting for the rest of the body. The task can then complete
/// successfully with only part of the body sent: a 16 MiB upload returned `200` after the upload
/// had reported 32768 of 16777216 bytes, and the connection stayed open, held by that request
/// until the server gave up on the body. Whether that happens or the whole body is sent depends
/// on how the answer reaches the client, so the same answer from the same server can follow a
/// whole upload or a cut one. A `2xx` never confirms that the whole body was sent: compare the
/// upload progress with the size of the body.
public struct DataTask<Content: Property>: RequestTask {

    // MARK: - Private properties

    private let task: RawTask<Content>

    // MARK: - Inits

    ///
    /// Initializes with a ``Property`` as its content.
    ///
    /// - Parameter content: The content of the request.
    ///
    public init(@PropertyBuilder content: () -> Content) {
        // The body is joined into one `Data` anyway, so there is no reason to cut it into fixed
        // chunks on the way. A `ReadingMode` property in `content` still overrides this.
        self.task = RawTask(content: content(), defaultReadingMode: .passthrough)
    }

    // MARK: - Public methods

    /// This method is used internally and should not be called directly.
    @_spi(Private)
    public func _result(environment: RequestEnvironmentValues) async throws -> TaskResult<Data> {
        try await task
            .collectData()
            ._result(environment: environment)
    }

    ///
    /// Resolves this task's request and hands it to `descriptor`, without performing it.
    ///
    /// - Parameter descriptor: The ``TaskDescriptor`` that produces the description.
    /// - Returns: The descriptor's output, a curl command line for ``CURLTaskDescriptor/cURL``.
    /// - Throws: An error thrown while resolving the request, or by the descriptor itself.
    ///
    public func description<Descriptor: TaskDescriptor>(_ descriptor: Descriptor) async throws -> Descriptor.Output {
        try await task.description(descriptor)
    }
}
