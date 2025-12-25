/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

extension Internals {

    final class ClientResponseReceiver: @unchecked Sendable, HTTPClientResponseDelegate {

        typealias Response = Void

        // MARK: - Private properties

        private let lock = Lock()

        private let url: String

        private let upload: Internals.AsyncStream<Int>
        private let head: Internals.AsyncStream<ResponseHead>
        private let cache: ((ResponseHead) -> Internals.AsyncStream<DataBuffer>?)?

        private let logger: Internals.TaskLogger?

        // MARK: - Unsafe properties

        private var _download: DownloadBuffer

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
            self._download = download
            self.cache = cache
            self.logger = logger
        }

        // MARK: - Internal methods

        func didSendRequestPart(task: HTTPClient.Task<Response>, _ part: IOData) {
            lock.withLockVoid {
                guard [.idle, .uploading].contains(_state) && _phase == .upload else {
                    return
                }

                _state = .uploading
                _reference = .upload

                upload.append(.success(part.readableBytes))
            }
        }

        func didSendRequest(task: HTTPClient.Task<Response>) {
            lock.withLockVoid {
                guard [.idle, .uploading].contains(_state) && _phase == .upload else {
                    return
                }

                _state = .uploading
                _phase = .upload
                _reference = .head

                upload.close()
            }
        }

        func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
            lock.withLock {
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

                self.head.append(.success(responseHead))
                self.upload.close()
                self.head.close()

                _state = .head
                _phase = .download
                _reference = .download

                if let cache = self.cache?(responseHead) {
                    _download.cacheStream(cache)
                }

                return task.eventLoop.makeSucceededVoidFuture()
            }
        }

        func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
            lock.withLock {
                guard [.head, .downloading].contains(_state) && _phase == .download else {
                    _unexpectedStateOrPhase()
                }

                _download.append(Internals.DataBuffer(
                    Internals.ByteURL(buffer)
                ))

                _state = .downloading
                _phase = .download
                _reference = .download

                head.close()

                return task.eventLoop.makeSucceededVoidFuture()
            }
        }

        func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
            lock.withLock {
                guard [.head, .downloading, .end].contains(_state) && _phase == .download else {
                    _unexpectedStateOrPhase()
                }

                _state = .end
                _phase = .download
                _reference = .lockout

                _download.close()
                head.close()
                upload.close()
            }
        }

        func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
            lock.withLockVoid {
                defer {
                    _state = .failure
                    upload.close()
                    head.close()
                    _download.close()
                }

                switch _state {
                case .idle:
                    guard _reference <= .head else {
                        fallthrough
                    }
                    head.append(.failure(error))
                case .uploading:
                    guard _reference <= .upload else {
                        fallthrough
                    }

                    upload.append(.failure(error))
                case .head:
                    guard _reference <= .head else {
                        fallthrough
                    }

                    head.append(.failure(error))
                case .downloading:
                    guard _reference <= .download else {
                        fallthrough
                    }

                    _download.failed(error)
                case .end, .failure:
                    _unexpectedStateOrPhase(error: error)
                }
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
