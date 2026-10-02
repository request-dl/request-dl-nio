//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import struct FoundationEssentials.Data
#else
import struct Foundation.Data
#endif

/// Observes requests as they run: how much of the request and response bodies has crossed the
/// network, and what state each execution is in.
///
/// ```swift
/// struct PrintMonitor: RequestMonitor {
///     func request(_ execution: RequestExecution, didDownload bytes: Int, total: Int, of expected: Int?) {
///         print("\(execution.url): \(total) of \(expected.map(String.init) ?? "?") bytes")
///     }
///
///     func request(_ execution: RequestExecution, didChange state: RequestState) {
///         print("\(execution.url): \(state)")
///     }
/// }
///
/// try await DataTask { ... }
///     .monitor(PrintMonitor())
///     .result()
/// ```
///
/// Attach one with ``RequestTask/monitor(_:)``. It works with any task, `DataTask` included, and
/// with a ``GroupTask``, where each ``RequestExecution`` says which request an event is about.
/// Implement only the methods you need: all of them do nothing by default.
///
/// ## What is counted
///
/// Bytes are counted where they cross the network, as the request runs, and not as your code
/// consumes them. So a download's progress keeps going while you are not reading its bytes, up to
/// what the transport buffers ahead of you, and a suspended request stops counting because it
/// stopped moving.
///
/// - Uploads count the request body handed to the transport.
/// - Downloads count the response body as the transport delivers it, after any decoding it did
///   itself, so with a content coding the count can be larger than the `Content-Length`. That is
///   why `expected` is left `nil` for a coded response.
///
/// ## Delivery
///
/// Events reach a monitor in order, one at a time, on a task of their own. A monitor that takes
/// its time never slows the transfer down, but it does not queue up progress either: byte counts
/// that arrive while a previous call is still running are merged into the next one, its `bytes`
/// being their sum and its `total` the latest. Only ``RequestState`` changes are never merged or
/// skipped.
public protocol RequestMonitor: Sendable {

    /// Part of the request body went out.
    ///
    /// - Parameters:
    ///   - execution: The execution this is about.
    ///   - bytes: Bytes sent since the previous call.
    ///   - total: Bytes sent since the request started.
    ///   - expected: The size of the request body, when it is known.
    func request(_ execution: RequestExecution, didUpload bytes: Int, total: Int, of expected: Int?)

    /// Part of the response body came in.
    ///
    /// - Parameters:
    ///   - execution: The execution this is about.
    ///   - bytes: Bytes received since the previous call.
    ///   - total: Bytes received since the request started.
    ///   - expected: The size of the response body, when the response states it (a
    ///   `Content-Length`, without a content coding).
    func request(_ execution: RequestExecution, didDownload bytes: Int, total: Int, of expected: Int?)

    /// The execution moved to a new state.
    func request(_ execution: RequestExecution, didChange state: RequestState)
}

extension RequestMonitor {

    public func request(_ execution: RequestExecution, didUpload bytes: Int, total: Int, of expected: Int?) {}

    public func request(_ execution: RequestExecution, didDownload bytes: Int, total: Int, of expected: Int?) {}

    public func request(_ execution: RequestExecution, didChange state: RequestState) {}
}
