//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOHTTP1

extension Internals {

    /// `ResponseAccumulator` that also records the transaction AsyncHTTPClient measures for the
    /// request it accumulates.
    ///
    /// `ResponseAccumulator` is `final`, so it is wrapped and everything it needs is forwarded to
    /// it. Only the buffered requests that are not the caller's own use this, such as the
    /// conditional request that asks whether a cached response still holds: a request that is
    /// streamed to the caller has `ClientResponseReceiver` for that.
    package final class MetricsCollectingAccumulator: HTTPClientResponseDelegate {

        package typealias Response = HTTPClient.Response

        // MARK: - Private properties

        private let accumulator: ResponseAccumulator
        private let metrics: Internals.RequestMetricsCollector
        private let source: Internals.TransactionMetrics.Source

        // MARK: - Inits

        package init(
            request: HTTPClient.Request,
            metrics: Internals.RequestMetricsCollector,
            source: Internals.TransactionMetrics.Source
        ) {
            self.accumulator = ResponseAccumulator(request: request)
            self.metrics = metrics
            self.source = source
        }

        // MARK: - Internal methods

        package func didVisitURL(
            task: HTTPClient.Task<HTTPClient.Response>,
            _ request: HTTPClient.Request,
            _ head: HTTPResponseHead
        ) {
            accumulator.didVisitURL(task: task, request, head)
        }

        package func didReceiveHead(
            task: HTTPClient.Task<HTTPClient.Response>,
            _ head: HTTPResponseHead
        ) -> EventLoopFuture<Void> {
            accumulator.didReceiveHead(task: task, head)
        }

        package func didReceiveBodyPart(
            task: HTTPClient.Task<HTTPClient.Response>,
            _ buffer: ByteBuffer
        ) -> EventLoopFuture<Void> {
            accumulator.didReceiveBodyPart(task: task, buffer)
        }

        package func didReceiveError(task: HTTPClient.Task<HTTPClient.Response>, _ error: Error) {
            accumulator.didReceiveError(task: task, error)
        }

        package func didFinishRequest(task: HTTPClient.Task<HTTPClient.Response>) throws -> HTTPClient.Response {
            try accumulator.didFinishRequest(task: task)
        }

        package func didCollectMetrics(
            task: HTTPClient.Task<HTTPClient.Response>,
            _ metrics: HTTPClientTransactionMetrics
        ) {
            var transaction = Internals.TransactionMetrics(metrics)
            transaction.source = source

            self.metrics.append(transaction)
        }
    }
}

#endif
