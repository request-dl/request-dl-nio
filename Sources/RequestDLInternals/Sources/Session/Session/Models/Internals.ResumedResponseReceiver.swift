//
// See LICENSE for this package's licensing information.
//

// HTTPClientResponseDelegate conformance: entirely .nio/.nioTransportServices-only.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import SwiftAsyncStream

extension Internals {

    /// Receives one continuation of a download that lost its connection mid-body: the exchange
    /// `Internals.NIODownloadReconnection` issues with `Range`/`If-Range`, feeding the rest of
    /// the body into the same `DownloadBuffer` the original `Internals.ClientResponseReceiver`
    /// was filling.
    ///
    /// Much narrower than that receiver: there's no request body, and nothing to report about
    /// the head, which the reader already got from the original exchange. What it adds is the
    /// check that the continuation is exactly the rest of the same representation
    /// (`Internals.RangeResumptionPlan.validate`), made on the head, before a single byte of the
    /// body is accepted: a mismatch fails the head's future, which makes AsyncHTTPClient abandon
    /// the exchange and report the mismatch through `didReceiveError`.
    ///
    /// Back pressure and suspension work exactly as on the original exchange, against the same
    /// window.
    final class ResumedResponseReceiver: @unchecked Sendable, HTTPClientResponseDelegate {

        typealias Response = Void

        /// Stops a continuation answered with "nothing left" (a `416` whose complete length is
        /// exactly what was delivered) before its body, and ends the download successfully.
        private struct AlreadyComplete: Error {}

        // MARK: - Private properties

        private let url: String
        private let download: Internals.DownloadBuffer
        private let attempt: Internals.DownloadResumptionState.Attempt
        private let reconnection: Internals.NIODownloadReconnection

        /// The cookie jar of the request this continues, if its session has one.
        private let cookies: Internals.CookieContext?
        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _isValidated = false
        private var _isOver = false
        private var _pausedPart: PausedBodyPart?

        // MARK: - Inits

        init(
            url: String,
            download: Internals.DownloadBuffer,
            attempt: Internals.DownloadResumptionState.Attempt,
            reconnection: Internals.NIODownloadReconnection,
            cookies: Internals.CookieContext? = nil
        ) {
            self.url = url
            self.download = download
            self.attempt = attempt
            self.reconnection = reconnection
            self.cookies = cookies
        }

        // MARK: - Internal methods

        /// Every hop of the continuation is stored with the URL of its own request, as for the
        /// request it continues.
        func didVisitURL(task: HTTPClient.Task<Response>, _ request: HTTPClient.Request, _ head: HTTPResponseHead) {
            cookies?.store(headerFields: head.headers.map { (name: $0.name, value: $0.value) }, for: request.url)
        }

        func willFollowRedirect(request: inout HTTPClient.Request) {
            guard let cookies, cookies.managesHeader else {
                return
            }

            request.headers.remove(name: "Cookie")

            if let value = cookies.cookieHeaderForHop(to: request.url) {
                request.headers.add(name: "Cookie", value: value)
            }
        }

        func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
            let responseHead = ResponseHead(
                url: url,
                status: .init(code: head.status.code, reason: head.status.reasonPhrase),
                version: .init(minor: head.version.minor, major: head.version.major),
                headers: head.headers.map { .init(name: $0.name, value: $0.value) },
                isKeepAlive: head.isKeepAlive
            )

            do {
                switch try attempt.plan.validate(responseHead, resumingAt: attempt.offset) {
                case .resume:
                    lock.withLock { _isValidated = true }
                    return task.eventLoop.makeSucceededVoidFuture()

                case .alreadyComplete:
                    return task.eventLoop.makeFailedFuture(AlreadyComplete())
                }
            } catch {
                return task.eventLoop.makeFailedFuture(error)
            }
        }

        func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
            // Unreachable for a head that failed validation (AsyncHTTPClient stops at the failed
            // future), kept as a guard all the same: accepting a single byte of a mismatched
            // continuation is the one thing this type exists to prevent.
            guard lock.withLock({ _isValidated && !_isOver }) else {
                return task.eventLoop.makeSucceededVoidFuture()
            }

            // Built synchronously and appended in delivery order, for the same reason as in
            // `Internals.ClientResponseReceiver.didReceiveBodyPart(task:_:)`.
            let chunk = Internals.Chunk(buffer)

            reconnection.didDeliver(chunk.readableBytes)
            download.append(chunk)

            let (future, pausedPart) = PausedBodyPart.gate(download.flowControl, on: task.eventLoop)

            if let pausedPart {
                lock.withLock { _pausedPart = pausedPart }
            }

            return future
        }

        func didCollectMetrics(task: HTTPClient.Task<Response>, _ metrics: HTTPClientTransactionMetrics) {
            reconnection.recordMetrics(metrics)
        }

        func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
            lock.withLock { _isOver = true }

            reconnection.observer?.didChange(.finished)
            reconnection.terminate { self.download.close() }
        }

        func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
            let isFirst = lock.withLock { () -> Bool in
                guard !_isOver else {
                    return false
                }

                _isOver = true
                return true
            }

            guard isFirst else {
                return
            }

            if error is AlreadyComplete {
                reconnection.observer?.didChange(.finished)
                reconnection.terminate { self.download.close() }
                return
            }

            if reconnection.claim(error) {
                // Another continuation takes over. Same as the original exchange's hand-over:
                // this one's paused part completes on its own, the shared window stays as it is.
                let pausedPart = lock.withLock { () -> PausedBodyPart? in
                    defer { _pausedPart = nil }
                    return _pausedPart
                }

                pausedPart?.complete()
                return
            }

            // See `Internals.ClientResponseReceiver.didReceiveError(task:_:)`.
            let error = Internals.RedirectError.translating(error)

            reconnection.observer?.didChange(.failed(error))
            reconnection.terminate { self.download.failed(error) }
        }

        /// See `Internals.ClientResponseReceiver.failIfNotStarted(_:)`: a pre-flight rejection
        /// never calls the delegate, and neither does AsyncHTTPClient when it fails the task of an
        /// exchange whose response was already received (the request body stream finishing after
        /// the connection was gone). Either would leave the body waiting on nobody.
        ///
        /// A no-op once the delegate was told the end of the exchange, by `didFinishRequest` or
        /// `didReceiveError`, or once another continuation took it over.
        func failIfNotStarted(_ error: Error) {
            let isFirst = lock.withLock { () -> Bool in
                guard !_isOver else {
                    return false
                }

                _isOver = true
                return true
            }

            if isFirst {
                reconnection.observer?.didChange(.failed(error))
                reconnection.terminate { self.download.failed(error) }
            }
        }
    }
}

#endif
