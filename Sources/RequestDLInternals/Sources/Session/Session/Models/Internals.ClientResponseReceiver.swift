//
// See LICENSE for this package's licensing information.
//

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

        private let logger: Internals.TaskLogger?

        // MARK: - Unsafe properties

        private var _phase: Phase = .upload
        private var _state: State = .idle
        private var _reference: StreamReference = .none

        // MARK: - Inits

        package init(
            url: String,
            upload: Internals.AsyncStream<Int>,
            head: Internals.AsyncStream<ResponseHead>,
            download: DownloadBuffer,
            cache: ((ResponseHead) -> Internals.AsyncStream<DataBuffer>?)?,
            logger: Internals.TaskLogger?
        ) {
            self.url = url
            self.upload = upload
            self.head = head
            self.download = download
            self.cache = cache
            self.logger = logger
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
                    { self.head.append(.success(responseHead)) },
                    { self.upload.close() },
                    { self.head.close() },
                    {
                        // The cache factory allocates a buffer and starts a task, so it is
                        // caller supplied work that has no business running under the lock.
                        guard let cacheStream = self.cache?(responseHead) else {
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
                return [{ self.download.append(dataBuffer) }]
            }

            return task.eventLoop.makeSucceededVoidFuture()
        }

        package func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
            decide {
                guard [.head, .downloading, .end].contains(_state) && _phase == .download else {
                    _unexpectedStateOrPhase()
                }

                _state = .end
                _phase = .download
                _reference = .lockout

                return [
                    { self.download.close() },
                    { self.head.close() },
                    { self.upload.close() },
                ]
            }
        }

        package func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
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

                    effects.append { self.download.failed(error) }
                case .end, .failure:
                    // Reported, not trapped. Must not call `_unexpectedStateOrPhase` here, which
                    // is `Never` and ends the process — reaching this branch does not require a
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
                effects.append { self.download.close() }

                return effects
            }
        }

        // MARK: - Private methods

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
