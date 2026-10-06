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

    /// A transaction of the execution was measured: one exchange on the wire, with the phases it went
    /// through and the connection it ran on.
    ///
    /// Called once for each transaction, so a request that follows a redirect or continues a download
    /// reports one for every exchange. It is independent of how the request ends, which is the point:
    /// a request that fails as a whole throws and has no ``TaskResult`` to read ``TaskResult/metrics``
    /// from, but the transactions it went through are reported here all the same.
    ///
    /// A response served from the cache is reported too, as a transaction with
    /// ``RequestMetrics/Transaction/Source/cache`` that has no connection, and so is the conditional
    /// request that asked whether the cache still held, with
    /// ``RequestMetrics/Transaction/Source/revalidation``, ahead of whatever followed it.
    ///
    /// When it arrives depends on the executor. AsyncHTTPClient reports a transaction before the
    /// execution ends. `URLSession` reports it once its task is done, which can be after the final
    /// ``RequestState``, and it only reports an error for the task as a whole, so
    /// ``RequestMetrics/Transaction/error`` can be missing here even when the execution failed. The
    /// ``RequestState/failed(_:)`` state carries the error.
    ///
    /// - Parameters:
    ///   - execution: The execution this is about.
    ///   - transaction: What was measured.
    func request(_ execution: RequestExecution, didCollect transaction: RequestMetrics.Transaction)
}

extension RequestMonitor {

    public func request(_ execution: RequestExecution, didUpload bytes: Int, total: Int, of expected: Int?) {}

    public func request(_ execution: RequestExecution, didDownload bytes: Int, total: Int, of expected: Int?) {}

    public func request(_ execution: RequestExecution, didChange state: RequestState) {}

    public func request(_ execution: RequestExecution, didCollect transaction: RequestMetrics.Transaction) {}
}
