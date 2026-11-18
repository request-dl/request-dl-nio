//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import AsyncHTTPClient
import NIOConcurrencyHelpers
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
        private let bodyless: Internals.BodylessResponse
        private let host: String
        private let cookies: Internals.CookieContext?
        private let lock = NIOLock()

        // MARK: - Unsafe properties

        private var _head: HTTPResponseHead?
        private var _hasBody = false
        private var _bodylessResponse: HTTPClient.Response?

        // MARK: - Inits

        package init(
            request: HTTPClient.Request,
            metrics: Internals.RequestMetricsCollector,
            source: Internals.TransactionMetrics.Source,
            cookies: Internals.CookieContext? = nil
        ) {
            self.accumulator = ResponseAccumulator(request: request)
            self.metrics = metrics
            self.source = source
            self.bodyless = Internals.BodylessResponse(method: request.method)
            self.host = request.host
            self.cookies = cookies
        }

        // MARK: - Package methods

        /// The response, for a request that failed only because the decompressor found nothing to
        /// decode in one that has no body (see `Internals.BodylessResponse`). Reading `error` as
        /// the failure of the request is for the caller to do when this has nothing to return.
        package func recovering(from error: any Error) throws -> HTTPClient.Response {
            guard let response = lock.withLock({ _bodylessResponse }) else {
                throw error
            }

            return response
        }

        // MARK: - Internal methods

        package func didVisitURL(
            task: HTTPClient.Task<HTTPClient.Response>,
            _ request: HTTPClient.Request,
            _ head: HTTPResponseHead
        ) {
            cookies?.store(headerFields: head.headers.map { (name: $0.name, value: $0.value) }, for: request.url)
            accumulator.didVisitURL(task: task, request, head)
        }

        package func willFollowRedirect(request: inout HTTPClient.Request) {
            guard let cookies, cookies.managesHeader else {
                return
            }

            request.headers.remove(name: "Cookie")

            if let value = cookies.cookieHeaderForRedirect(to: request.url) {
                request.headers.add(name: "Cookie", value: value)
            }
        }

        package func didReceiveHead(
            task: HTTPClient.Task<HTTPClient.Response>,
            _ head: HTTPResponseHead
        ) -> EventLoopFuture<Void> {
            lock.withLock {
                _head = head
            }

            return accumulator.didReceiveHead(task: task, head)
        }

        package func didReceiveBodyPart(
            task: HTTPClient.Task<HTTPClient.Response>,
            _ buffer: ByteBuffer
        ) -> EventLoopFuture<Void> {
            lock.withLock {
                _hasBody = true
            }

            return accumulator.didReceiveBodyPart(task: task, buffer)
        }

        package func didReceiveError(task: HTTPClient.Task<HTTPClient.Response>, _ error: Error) {
            let response = lock.withLock { () -> HTTPClient.Response? in
                guard let head = _head, !_hasBody, bodyless.isBodyless(head), bodyless.isTruncatedDecoder(error) else {
                    return nil
                }

                let response = HTTPClient.Response(
                    host: host,
                    status: head.status,
                    version: head.version,
                    headers: head.headers,
                    body: nil
                )

                _bodylessResponse = response
                return response
            }

            guard response == nil else {
                return
            }

            accumulator.didReceiveError(task: task, error)
        }

        package func didFinishRequest(task: HTTPClient.Task<HTTPClient.Response>) throws -> HTTPClient.Response {
            try accumulator.didFinishRequest(task: task)
        }

        package func didCollectMetrics(
            task: HTTPClient.Task<HTTPClient.Response>,
            _ metrics: HTTPClientTransactionMetrics
        ) {
            let isBodylessResponse = lock.withLock { () -> Bool in
                guard let head = _head, !_hasBody else {
                    return false
                }

                return bodyless.isBodyless(head)
            }

            var transaction = bodyless.reporting(
                Internals.TransactionMetrics(metrics),
                isBodylessResponse: isBodylessResponse
            )
            transaction.source = source

            self.metrics.append(transaction)
        }
    }
}

#endif
