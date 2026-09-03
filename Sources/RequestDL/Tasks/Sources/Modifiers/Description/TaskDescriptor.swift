//
// See LICENSE for this package's licensing information.
//

/// Produces a description of a resolved request without performing it.
///
/// ``DataTask``, ``DownloadTask``, and ``UploadTask`` each expose a generic
/// ``RequestTask/description(_:)`` that resolves their `Property` content the same way
/// ``RequestTask/result()`` would, then hands the outcome to a `TaskDescriptor` instead of
/// executing the request over the network.
///
/// ``CURLTaskDescriptor`` is the built-in conformance, selected via `.cURL`:
///
/// ```swift
/// let command = try await DataTask {
///     BaseURL("example.com")
///     Payload(data: someData)
/// }
/// .description(.cURL)
/// ```
///
/// A custom descriptor conforms the same way any other strategy type in RequestDL does — see
/// ``RequestTaskModifier``/``RequestTaskInterceptor`` for the same shape — and picks up whatever
/// ``TaskDescriptorContext`` already carries. There is nothing curl-specific about the mechanism
/// itself.
public protocol TaskDescriptor<Output>: Sendable {

    associatedtype Output: Sendable

    ///
    /// Produces this descriptor's output from a resolved request.
    ///
    /// - Parameter context: The resolved request, plus anything the graph walk captured that the
    /// final configuration alone can't represent.
    /// - Returns: This descriptor's output.
    /// - Throws: Any error raised while producing the output.
    ///
    func describe(_ context: TaskDescriptorContext) async throws -> Output
}
