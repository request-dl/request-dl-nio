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
        self.task = RawTask(content: content())
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
