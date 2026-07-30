/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import SwiftAsyncStream

extension Internals {

    final class ClientResponseReceiver: @unchecked Sendable, HTTPClientResponseDelegate {

        typealias Response = Void

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

        init(
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

        func didSendRequestPart(task: HTTPClient.Task<Response>, _ part: IOData) {
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

        func didSendRequest(task: HTTPClient.Task<Response>) {
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

        func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
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
                    headers: .init(head.headers),
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
                    }
                ]
            }

            return task.eventLoop.makeSucceededVoidFuture()
        }

        func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
            decide {
                guard [.head, .downloading].contains(_state) && _phase == .download else {
                    _unexpectedStateOrPhase()
                }

                _state = .downloading
                _phase = .download
                _reference = .download

                let dataBuffer = Internals.DataBuffer(Internals.ByteURL(buffer))

                return [
                    { self.download.append(dataBuffer) },
                    { self.head.close() }
                ]
            }

            return task.eventLoop.makeSucceededVoidFuture()
        }

        func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
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
                    { self.upload.close() }
                ]
            }
        }

        func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
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
                    _unexpectedStateOrPhase(error: error)
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
            effects.forEach { $0() }
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

    enum State {
        case idle
        case uploading
        case head
        case downloading
        case end
        case failure
    }
}

extension Internals.ClientResponseReceiver {

    enum Phase {
        case upload
        case download
    }

    enum StreamReference: Int, Comparable {

        case none
        case upload
        case head
        case download
        case lockout

        static func < (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
