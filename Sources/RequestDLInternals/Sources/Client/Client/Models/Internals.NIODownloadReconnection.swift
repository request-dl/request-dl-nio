//
// See LICENSE for this package's licensing information.
//

// Drives AsyncHTTPClient exchanges: .nio/.nioTransportServices only.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import SwiftAsyncStream

#if canImport(Network)
import Network
#endif

extension Internals {

    /// Keeps one `.nio` download going across lost connections: the `.nio` counterpart to
    /// `Internals.URLSessionClient.resumeDownload`, sharing its plan, validation and budget
    /// (`Internals.RangeResumptionPlan`, `Internals.DownloadResumptionState`).
    ///
    /// The original exchange's `Internals.ClientResponseReceiver`, and every continuation's
    /// `Internals.ResumedResponseReceiver`, report to it: the bytes they deliver, and any failure
    /// mid-body, which it either ``claim(_:)``s -- starting a continuation with `Range`/`If-Range`
    /// from exactly the delivered count -- or leaves to end the body as before.
    ///
    /// ## Ending exactly once
    ///
    /// The body can now outlive any single exchange, so ending it is no longer any one receiver's
    /// call: every ending goes through ``terminate(_:)``, whose first caller alone closes or fails
    /// the body and releases everything the download holds -- its window, the execution's
    /// `Internals.TransferControl`, and the operation keeping the client busy between exchanges.
    /// A cancellation that lands *between* two exchanges, where no receiver is left to report it,
    /// ends the body itself (``cancel()``).
    ///
    /// ## Suspension
    ///
    /// A continuation only starts once the execution isn't suspended: a connection lost *because*
    /// of a long suspension (a server or middlebox idle timeout, say) is reconnected when the
    /// application resumes, not while it still wants the transfer held back.
    package final class NIODownloadReconnection: @unchecked Sendable {

        // MARK: - Private properties

        private let client: Internals.Client
        private let request: HTTPClient.Request
        private let url: String
        private let download: Internals.DownloadBuffer
        private let flowControl: Internals.FlowControlWindow
        private let transferControl: Internals.TransferControl
        private let logger: Internals.TaskLogger?
        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _state: Internals.DownloadResumptionState
        private var _operation: Internals.ClientOperation?
        private var _attemptSeed: Internals.TaskSeed?
        private var _reconnecting: Task<Void, Never>?
        private var _isBetweenExchanges = false
        private var _isCancelled = false
        private var _isTerminated = false

        // MARK: - Inits

        /// - Parameter request: The original request, bodyless (only a bodyless `GET` is ever
        ///   resumed); continuations are copies of it with `Range`/`If-Range` added.
        init(
            client: Internals.Client,
            request: HTTPClient.Request,
            url: String,
            download: Internals.DownloadBuffer,
            flowControl: Internals.FlowControlWindow,
            transferControl: Internals.TransferControl,
            policy: Internals.DownloadResumptionPolicy,
            logger: Internals.TaskLogger?
        ) {
            self.client = client
            self.request = request
            self.url = url
            self.download = download
            self.flowControl = flowControl
            self.transferControl = transferControl
            self.logger = logger
            self._state = .init(policy: policy)
            self._operation = client.holdOperation()
        }

        // MARK: - Internal methods (receivers)

        func didReceiveOriginalHead(_ head: Internals.ResponseHead) {
            let method = request.method.rawValue
            let headerNames = request.headers.map(\.name)

            lock.withLock {
                _state.didReceiveOriginalHead(head, method: method, requestHeaderNames: headerNames)
            }
        }

        func didDeliver(_ bytes: Int) {
            lock.withLock {
                _state.deliveredBytes += Int64(bytes)
            }
        }

        /// Takes over a failure mid-body, when it's one a continuation can recover from and the
        /// budget allows another.
        ///
        /// - Returns: `true` if a continuation will follow. The caller must then leave the body,
        ///   and its window, alone.
        func claim(_ error: Error) -> Bool {
            guard Self.isTransientTransportFailure(error) else {
                return false
            }

            let attempt = lock.withLock { () -> Internals.DownloadResumptionState.Attempt? in
                guard !_isCancelled, !_isTerminated, let attempt = _state.nextAttempt() else {
                    return nil
                }

                _isBetweenExchanges = true
                return attempt
            }

            guard let attempt else {
                return false
            }

            let reconnecting = Task {
                await self.reconnect(attempt)
            }

            let isOver = lock.withLock { () -> Bool in
                guard !_isTerminated else {
                    return true
                }

                _reconnecting = reconnecting
                return false
            }

            if isOver {
                reconnecting.cancel()
            }

            return true
        }

        /// Ends the download, if nothing has yet: runs `end` (which closes or fails the body) and
        /// releases what the download holds. A no-op for every call after the first.
        func terminate(_ end: () -> Void) {
            typealias Taken = (Internals.ClientOperation?, Task<Void, Never>?, Internals.TaskSeed?)

            let taken = lock.withLock { () -> Taken? in
                guard !_isTerminated else {
                    return nil
                }

                _isTerminated = true
                _isBetweenExchanges = false

                defer {
                    _operation = nil
                    _reconnecting = nil
                    _attemptSeed = nil
                }

                return (_operation, _reconnecting, _attemptSeed)
            }

            guard let (operation, reconnecting, attemptSeed) = taken else {
                return
            }

            end()

            reconnecting?.cancel()
            flowControl.release()
            transferControl.release()
            operation?.complete()

            // Let go of here, outside the lock: by now its exchange is over (or being cancelled),
            // so releasing it cancels nothing that's still wanted, and it's what breaks the
            // reference cycle through that exchange's own receiver.
            withExtendedLifetime(attemptSeed) {}
        }

        // MARK: - Internal methods (seed)

        /// Cancels the download: whichever continuation is running (whose receiver then ends the
        /// body with the cancellation), or, between two exchanges, the body itself. The original
        /// exchange is cancelled by the seed that owns it, alongside this.
        func cancel() {
            let (attemptSeed, isBetweenExchanges) = lock.withLock { () -> (Internals.TaskSeed?, Bool) in
                _isCancelled = true
                return (_attemptSeed, _isBetweenExchanges)
            }

            if isBetweenExchanges {
                terminate {
                    download.failed(HTTPClientError.cancelled)
                }
            }

            attemptSeed?()
        }

        // MARK: - Private methods

        /// Told about the execution as it happens, when something observes it.
        var observer: Internals.ExecutionObserver? {
            transferControl.observer
        }

        private func reconnect(_ attempt: Internals.DownloadResumptionState.Attempt) async {
            // Released, like everything else, once the download ends; that is what ends this
            // wait if it's cancelled while suspended.
            await transferControl.waitUntilResumed()

            let delay = lock.withLock { _state.policy.delay }

            if delay > .zero {
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled, !lock.withLock({ _isCancelled || _isTerminated }) else {
                return
            }

            observer?.didChange(.reconnecting(attempt: attempt.number))

            var continuation = request

            for header in attempt.headers {
                continuation.headers.replaceOrAdd(name: header.name, value: header.value)
            }

            let receiver = ResumedResponseReceiver(
                url: url,
                download: download,
                attempt: attempt,
                reconnection: self
            )

            // `execute` now throws when the request is rejected before dispatch; that ends this
            // attempt the same way a failure of the task itself would.
            let unsafeTask: Internals.UnsafeTask<Void>
            do {
                unsafeTask = try await client.execute(
                    request: continuation,
                    delegate: receiver,
                    logger: logger
                )
            } catch {
                receiver.failIfNotStarted(error)
                return
            }

            unsafeTask.whenFailure { error in
                receiver.failIfNotStarted(error)
            }

            let attemptSeed = unsafeTask()

            // Replacing the previous exchange's seed is fine: that exchange already ended, so
            // releasing its seed cancels nothing.
            let isCancelled = lock.withLock { () -> Bool in
                guard !_isCancelled, !_isTerminated else {
                    return true
                }

                _attemptSeed = attemptSeed
                _isBetweenExchanges = false
                return false
            }

            if isCancelled {
                attemptSeed()
            }
        }

        // MARK: - Internal static methods

        /// Whether `error` means the connection was lost or couldn't be (re)established -- what a
        /// continuation can recover from -- rather than a cancellation, a TLS/trust or
        /// redirect-policy failure, or a protocol error, which it can't.
        package static func isTransientTransportFailure(_ error: Error) -> Bool {
            if let error = error as? HTTPClientError {
                return [
                    .remoteConnectionClosed,
                    .readTimeout,
                    .writeTimeout,
                    .connectTimeout,
                    .tlsHandshakeTimeout,
                    .getConnectionFromPoolTimeout,
                    .uncleanShutdown,
                ].contains(error)
            }

            // What a connection closed mid-body actually surfaces as over HTTP/1.1: the parser
            // reaching end-of-stream before the body's declared end (`Content-Length` not reached,
            // or a chunked body without its terminating chunk). Observed directly, for both
            // framings; `remoteConnectionClosed` only covers a close before the head.
            if let error = error as? HTTPParserError, error == .invalidEOFState {
                return true
            }

            if error is IOError || error is NIOConnectionError {
                return true
            }

            if let error = error as? ChannelError {
                switch error {
                case .ioOnClosedChannel, .eof, .outputClosed, .alreadyClosed, .connectTimeout:
                    return true
                default:
                    return false
                }
            }

            if let error = error as? NIOSSLError, case .uncleanShutdown = error {
                return true
            }

            #if canImport(Network)
            if let error = error as? NWError, case .posix = error {
                return true
            }

            if isNetworkFrameworkConnectionLoss(error) {
                return true
            }
            #endif

            return false
        }

        #if canImport(Network)
        /// What SwiftNIO's Network.framework transport (`NIOTransportServices`) reports when the
        /// connection is reset, closed or unreachable: its own `NWPOSIXError`, which wraps the
        /// `POSIXErrorCode` and is not an `NWError`.
        ///
        /// Recognised by name and by the code it wraps, since that module is a dependency of
        /// AsyncHTTPClient and not one of this target's own, and a connection lost while a request
        /// body is being written is reported this way.
        private static func isNetworkFrameworkConnectionLoss(_ error: Error) -> Bool {
            guard String(reflecting: type(of: error)).hasSuffix("NWPOSIXError") else {
                return false
            }

            guard
                let code = Mirror(reflecting: error).children.first(where: { $0.label == "errorCode" })?.value
                    as? POSIXErrorCode
            else {
                return false
            }

            switch code {
            case .ECONNRESET, .EPIPE, .ECONNABORTED, .ETIMEDOUT, .ENOTCONN, .ENETDOWN, .ENETUNREACH,
                .EHOSTUNREACH, .ECONNREFUSED:
                return true
            default:
                return false
            }
        }
        #endif
    }
}

#endif
