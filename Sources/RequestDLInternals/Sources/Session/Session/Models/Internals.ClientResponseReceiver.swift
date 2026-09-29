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

    package final class ClientResponseReceiver: @unchecked Sendable, HTTPClientResponseDelegate {

        package typealias Response = Void

        /// A stream operation deferred until the state lock is released.
        private typealias Effect = () -> Void

        // MARK: - Private properties

        private let lock = Lock()

        private let url: String

        private let upload: Internals.AsyncStream<Int>
        private let head: Internals.AsyncStream<ResponseHead>
        private let download: DownloadBuffer
        private let cache: ((ResponseHead) -> Internals.AsyncStream<DataBuffer>?)?
        private let decompressionDispatch: Internals.ManualDecompressionDispatch

        private let logger: Internals.TaskLogger?

        /// Released, like `download`'s window, once this exchange has ended for good; see
        /// `Internals.TransferControl.release()`.
        private let transferControl: Internals.TransferControl?

        /// Set when a lost connection may be recovered from: the body's bytes are counted as they
        /// are delivered, a transport failure mid-body is handed over to it instead of ending the
        /// body, and the body is only ever ended through it (see `endDownload(_:)`).
        private let reconnection: Internals.NIODownloadReconnection?

        // MARK: - Unsafe properties

        private var _phase: Phase = .upload
        private var _state: State = .idle
        private var _reference: StreamReference = .none

        /// The body part AsyncHTTPClient is currently held back on, if any.
        private var _pausedPart: PausedBodyPart?

        /// Set once `reconnection` took the rest of the body over from this exchange.
        private var _isHandedOver = false

        // MARK: - Inits

        package init(
            url: String,
            upload: Internals.AsyncStream<Int>,
            head: Internals.AsyncStream<ResponseHead>,
            download: DownloadBuffer,
            cache: ((ResponseHead) -> Internals.AsyncStream<DataBuffer>?)?,
            decompressionDispatch: Internals.ManualDecompressionDispatch,
            logger: Internals.TaskLogger?,
            transferControl: Internals.TransferControl? = nil,
            reconnection: Internals.NIODownloadReconnection? = nil
        ) {
            self.url = url
            self.upload = upload
            self.head = head
            self.download = download
            self.cache = cache
            self.decompressionDispatch = decompressionDispatch
            self.logger = logger
            self.transferControl = transferControl
            self.reconnection = reconnection
        }

        // MARK: - Internal methods

        package func didSendRequestPart(task: HTTPClient.Task<Response>, _ part: IOData) {
            decide {
                guard [.idle, .uploading].contains(_state) && _phase == .upload else {
                    return []
                }

                _state = .uploading
                _reference = .upload

                let readableBytes = part.readableBytes
                return [{ self.upload.append(.success(readableBytes)) }]
            }
        }

        package func didSendRequest(task: HTTPClient.Task<Response>) {
            decide {
                guard [.idle, .uploading].contains(_state) && _phase == .upload else {
                    return []
                }

                _state = .uploading
                _phase = .upload
                _reference = .head

                return [{ self.upload.close() }]
            }
        }

        package func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void>
        {
            decide {
                guard
                    ([.idle, .uploading].contains(_state) && _phase == .upload)
                        || [.head].contains(_state) && _phase == .download
                else {
                    _unexpectedStateOrPhase()
                }

                let responseHead = ResponseHead(
                    url: url,
                    status: ResponseHead.Status(
                        code: head.status.code,
                        reason: head.status.reasonPhrase
                    ),
                    version: ResponseHead.Version(
                        minor: head.version.minor,
                        major: head.version.major
                    ),
                    headers: head.headers.map { ResponseHead.HeaderField(name: $0.name, value: $0.value) },
                    isKeepAlive: head.isKeepAlive
                )

                _state = .head
                _phase = .download
                _reference = .download

                return [
                    // First, so whether this download can be resumed is settled before any part
                    // of its body is counted.
                    { self.reconnection?.didReceiveOriginalHead(responseHead) },
                    { self.head.append(.success(responseHead)) },
                    { self.upload.close() },
                    { self.head.close() },
                    {
                        // The cache factory allocates a buffer and starts a task, so it is
                        // caller supplied work that has no business running under the lock.
                        //
                        // Skipped whenever this response still needs this package's own
                        // decompression: the tee below captures wire bytes upstream of that
                        // step, so caching here would persist the still-compressed body under a
                        // cached head that (on replay, which never re-runs decompression) claims
                        // it's already decoded. See `Internals.ManualDecompressionDispatch
                        // .requiresManualDecoding(for:)`.
                        guard
                            !self.decompressionDispatch.requiresManualDecoding(for: responseHead),
                            let cacheStream = self.cache?(responseHead)
                        else {
                            return
                        }

                        self.download.cacheStream(cacheStream)
                    },
                ]
            }

            return task.eventLoop.makeSucceededVoidFuture()
        }

        package func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void>
        {
            // Built before the lock, and synchronously.
            //
            // Wrapping a `ByteBuffer` costs nothing: the store is already in memory and the
            // synchronous initializer exists precisely because that path never suspends. See
            // `Internals.Buffer.init(_ url: Internals.ByteURL)`.
            //
            // It must not become a detached task instead. `download.append` enqueues on a queue
            // that runs operations in submission order, and submission is synchronous, so
            // reassembly depends on parts being submitted in the order the event loop delivered
            // them. Two tasks racing to enqueue would corrupt the body.
            let dataBuffer = Internals.DataBuffer(Internals.ByteURL(buffer))

            decide {
                guard [.head, .downloading].contains(_state) && _phase == .download else {
                    _unexpectedStateOrPhase()
                }

                _state = .downloading
                _phase = .download
                _reference = .download

                // `head` is closed by `didReceiveHead`, and closing is idempotent, so repeating
                // it once per body part achieved nothing.
                return [
                    // Counted as it is handed over: the offset a continuation would resume from
                    // is exactly what the reader gets.
                    { self.reconnection?.didDeliver(dataBuffer.readableBytes) },
                    { self.download.append(dataBuffer) },
                ]
            }

            // The returned future is AsyncHTTPClient's back pressure: it reads nothing more from
            // this connection until it completes. Completing it unconditionally, as this used
            // to, let the network run arbitrarily far ahead of the reader, with the whole
            // difference held in memory.
            //
            // So it only completes once `download`'s window has room again, and that window is
            // drained by whoever finally reads the body -- through any decompression stage in
            // between, which meters its own output the same way -- not by `download`'s own
            // queue catching up, which is an in-memory copy and would throttle nothing.
            //
            // Checked after `decide`, whose effects already ran `download.append` and so
            // already charged this part. Waiting here never blocks the event loop's thread; it
            // only stops this one request from reading. Every way this exchange can end without
            // the reader draining the window releases it instead: `didReceiveError`,
            // `didFinishRequest`, the reader's iterator going away, and the request being
            // cancelled or dropped (see `Internals.Client.execute(request:url:...)`).
            //
            // A suspended window is shut the same way, so this is also where a suspension holds
            // the connection (see `Internals.TransferControl`).
            let (future, pausedPart) = PausedBodyPart.gate(download.flowControl, on: task.eventLoop)

            if let pausedPart {
                lock.withLock { _pausedPart = pausedPart }
            }

            return future
        }

        package func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
            // Nothing can be waiting on the window by now -- AsyncHTTPClient only finishes once
            // the last part's future completed -- but nothing will be produced into it again
            // either, so there is no reason to leave it able to pause.
            download.flowControl?.release()
            transferControl?.release()

            decide {
                guard [.head, .downloading, .end].contains(_state) && _phase == .download else {
                    _unexpectedStateOrPhase()
                }

                _state = .end
                _phase = .download
                _reference = .lockout

                return [
                    endDownload { self.download.close() },
                    { self.head.close() },
                    { self.upload.close() },
                ]
            }
        }

        package func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
            // A connection lost mid-body that a continuation can recover from ends only this
            // exchange, not the body: nothing below applies, the window in particular, which
            // the continuation goes on using.
            if let reconnection, handOver(error, to: reconnection) {
                return
            }

            // A late or repeated error for an exchange whose body a continuation already took
            // over must not touch anything shared with it either: the releases below would leave
            // the continuation unmetered and deaf to a suspension.
            guard !lock.withLock({ _isHandedOver }) else {
                return
            }

            // First, unconditionally, and outside the state machine: whatever state this error
            // lands in, including the `.end`/`.failure` ones that otherwise do nothing, a
            // `didReceiveBodyPart` future still waiting on the window must complete. Left
            // pending, it is an `EventLoopPromise` nobody will ever fulfil.
            //
            // Safe to fulfil synchronously, here on the event loop: AsyncHTTPClient moves its own
            // state to finished before calling this, so the continuation that runs inline only
            // finds that out and returns.
            download.flowControl?.release()
            transferControl?.release()

            decide {
                var effects = [Effect]()

                // The cascade picks the furthest stream the request actually reached, so the
                // error surfaces where a consumer is listening.
                switch _state {
                case .idle:
                    guard _reference <= .head else {
                        fallthrough
                    }

                    effects.append { self.head.append(.failure(error)) }
                case .uploading:
                    guard _reference <= .upload else {
                        fallthrough
                    }

                    effects.append { self.upload.append(.failure(error)) }
                case .head:
                    guard _reference <= .head else {
                        fallthrough
                    }

                    effects.append { self.head.append(.failure(error)) }
                case .downloading:
                    guard _reference <= .download else {
                        fallthrough
                    }

                    effects.append(endDownload { self.download.failed(error) })
                case .end, .failure:
                    // Reported, not trapped. Must not call `_unexpectedStateOrPhase` here, which
                    // is `Never` and ends the process: reaching this branch does not require a
                    // bug on this side. The delegate is driven by the network stack, and an error
                    // arriving after `didFinishRequest`, or a second error after the first, lands
                    // here. The cascade below can also walk into it on its own, since
                    // `didFinishRequest` sets `_reference` to `.lockout` and every `guard` in the
                    // chain then fails.
                    //
                    // Killing an app over the order two callbacks fired in is not a trade worth
                    // making. Preconditions are for invariants this package controls.
                    Internals.Log.unexpectedStateOrPhase(
                        state: _state,
                        phase: _phase,
                        error: error
                    ).log(level: .error, logger: logger?.logger)

                    return []
                }

                _state = .failure

                effects.append { self.upload.close() }
                effects.append { self.head.close() }
                effects.append(endDownload { self.download.close() })

                return effects
            }
        }

        /// Fails the streams as though the request had failed before this delegate was ever
        /// invoked: the outcome of a pre-flight rejection (`HTTPClient.Task.failedTask`, used
        /// e.g. for `.invalidRedirectConfiguration`/`.alreadyShutdown`), which resolves the
        /// task's own `futureResult` without calling any delegate method.
        ///
        /// Left alone, that failure is silent: this delegate never learns the request is over,
        /// so `head`/`upload`/`download` never close and whoever is awaiting them hangs forever.
        ///
        /// Guarded by the same lock/state machine as every real callback, so it is a no-op once
        /// the delegate has actually been driven, which is exactly the case a pre-flight
        /// rejection never reaches, since it calls this delegate zero times.
        package func failIfNotStarted(_ error: Error) {
            decide {
                guard _state == .idle, _reference == .none else {
                    return []
                }

                _state = .failure

                return [
                    { self.transferControl?.release() },
                    { self.head.append(.failure(error)) },
                    { self.upload.close() },
                    endDownload { self.download.close() },
                ]
            }
        }

        // MARK: - Private methods

        /// Hands a failure mid-body over to `reconnection`, when it can recover from it.
        ///
        /// - Returns: `true` if a continuation now owns the rest of the body. This exchange is then
        ///   over, and only this exchange: its paused body part, if any, completes on its own,
        ///   without releasing the window the continuation shares.
        private func handOver(_ error: Error, to reconnection: Internals.NIODownloadReconnection) -> Bool {
            let isMidBody = lock.withLock {
                [.head, .downloading].contains(_state) && _phase == .download
            }

            guard isMidBody, reconnection.claim(error) else {
                return false
            }

            let pausedPart = lock.withLock { () -> PausedBodyPart? in
                _state = .failure
                _reference = .lockout
                _isHandedOver = true

                defer { _pausedPart = nil }
                return _pausedPart
            }

            pausedPart?.complete()
            return true
        }

        /// Ends `download` directly, or, with a `reconnection`, through it: there, the body can
        /// outlive this exchange, and whichever exchange (or cancellation) ends it first is the
        /// only one that may.
        private func endDownload(_ body: @escaping () -> Void) -> Effect {
            {
                if let reconnection = self.reconnection {
                    reconnection.terminate(body)
                } else {
                    body()
                }
            }
        }

        /// Runs `body` under the state lock and its returned side effects after releasing it.
        ///
        /// Appending to or closing a stream resumes consumer continuations synchronously, and
        /// these callbacks run on the NIO event loop. Doing that inside the critical section
        /// would hand the event loop's thread to arbitrary consumer code while the receiver's
        /// lock is held, which is a priority inversion sitting directly on the network path.
        private func decide(_ body: () -> [Effect]) {
            let effects = lock.withLock(body)
            for effect in effects {
                effect()
            }
        }

        // MARK: - Unsafe methods

        private func _unexpectedStateOrPhase(error: Error? = nil, line: UInt = #line) -> Never {
            Internals.Log.unexpectedStateOrPhase(
                state: _state,
                phase: _phase,
                error: error
            ).preconditionFailure(line: line, logger: logger?.logger)
        }
    }
}

extension Internals.ClientResponseReceiver {

    package enum State {
        case idle
        case uploading
        case head
        case downloading
        case end
        case failure
    }
}

extension Internals.ClientResponseReceiver {

    package enum Phase {
        case upload
        case download
    }

    package enum StreamReference: Int, Comparable {

        case none
        case upload
        case head
        case download
        case lockout

        package static func < (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

#endif
