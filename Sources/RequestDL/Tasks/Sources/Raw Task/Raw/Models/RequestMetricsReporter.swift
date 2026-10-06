//
// See LICENSE for this package's licensing information.
//

import Dispatch
import Metrics
import RequestDLInternals
import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URLComponents
#endif

/// Reports to a `MetricsFactory` what one execution measured: how long it took, how much was sent
/// and how much was received.
///
/// One measurement per execution, taken when it ends, so a request that follows redirects is one,
/// and so is a download that reconnects. It is fed by the same events a `RequestMonitor` hears,
/// which is what makes it cover a request that fails, whatever executor sent it.
///
/// What is reported follows the names of the OpenTelemetry HTTP client metrics where they exist,
/// with these differences: the status is its class (`2xx`) rather than its code, to keep the
/// labels few; there is no protocol version, since the `URLSession` executor still reports a
/// nominal one; and the duration is a `Timer`, which `swift-metrics` records in nanoseconds,
/// where OpenTelemetry has seconds.
final class RequestMetricsReporter: @unchecked Sendable {

    // MARK: - Internal static properties

    static let durationLabel = "http.client.request.duration"
    static let requestBodySizeLabel = "http.client.request.body.size"
    static let responseBodySizeLabel = "http.client.response.body.size"

    // MARK: - Private properties

    private let factory: any MetricsFactory
    private let method: String
    private let host: String?
    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _startedAt: UInt64?
    private var _statusCode: Int?
    private var _uploaded = 0
    private var _downloaded = 0

    // MARK: - Inits

    init(factory: any MetricsFactory, execution: RequestExecution) {
        self.factory = factory
        self.method = Self.normalized(method: execution.method)
        self.host = URLComponents(string: execution.url)?.host.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Internal methods

    func receive(_ event: Internals.ExecutionObserver.Event) {
        switch event {
        case .progress(let upload, let download):
            lock.withLock {
                if let upload {
                    _uploaded = upload.total
                }

                if let download {
                    _downloaded = download.total
                }
            }

        case .head(let statusCode):
            lock.withLock { _statusCode = statusCode }

        case .state(.started):
            lock.withLock { _startedAt = DispatchTime.now().uptimeNanoseconds }

        case .state(.finished):
            report(failure: nil)

        case .state(.failed(let error)):
            report(failure: error)

        case .state, .metrics:
            break
        }
    }

    // MARK: - Private methods

    private func report(failure: (any Error)?) {
        let (startedAt, statusCode, uploaded, downloaded) = lock.withLock {
            (_startedAt, _statusCode, _uploaded, _downloaded)
        }

        // A response that finished without a head was served from the cache: nothing was sent,
        // and what it took is not what a request takes.
        guard failure != nil || statusCode != nil else {
            return
        }

        var dimensions = [("http.request.method", method)]

        if let host {
            dimensions.append(("server.address", host))
        }

        if let statusCode {
            dimensions.append(("http.response.status_class", "\(statusCode / 100)xx"))
        }

        if let failure {
            dimensions.append(("error.type", Self.errorType(of: failure)))
        }

        if let startedAt {
            let elapsed = DispatchTime.now().uptimeNanoseconds &- startedAt

            Timer(label: Self.durationLabel, dimensions: dimensions, factory: factory)
                .recordNanoseconds(Int64(clamping: elapsed))
        }

        if uploaded > .zero {
            Recorder(label: Self.requestBodySizeLabel, dimensions: dimensions, aggregate: true, factory: factory)
                .record(Int64(uploaded))
        }

        if statusCode != nil {
            Recorder(label: Self.responseBodySizeLabel, dimensions: dimensions, aggregate: true, factory: factory)
                .record(Int64(downloaded))
        }
    }

    // MARK: - Private static methods

    /// The methods HTTP defines, and `_OTHER` for the rest: a label can not be left to whatever a
    /// caller writes there.
    private static func normalized(method: String) -> String {
        let method = method.uppercased()

        switch method {
        case "GET", "HEAD", "POST", "PUT", "DELETE", "CONNECT", "OPTIONS", "TRACE", "PATCH":
            return method
        default:
            return "_OTHER"
        }
    }

    private static func errorType(of error: any Error) -> String {
        if error is ResourceTimeoutError || error is Internals.ResourceTimeoutError {
            return "timeout"
        }

        if error is CancellationError || error is Internals.TaskCancelledError {
            return "cancelled"
        }

        return String(describing: type(of: error))
    }
}
