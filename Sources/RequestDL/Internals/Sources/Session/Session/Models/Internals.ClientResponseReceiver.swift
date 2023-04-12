/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

extension Internals {

    class ClientResponseReceiver: HTTPClientResponseDelegate {

        typealias Response = Void

        let url: String
        let upload: DataStream<Int>
        let head: DataStream<ResponseHead>
        var download: DownloadBuffer

        var phase: Phase = .upload
        var state: State = .idle
        var reference: StreamReference = .none

        init(
            url: String,
            upload: DataStream<Int>,
            head: DataStream<ResponseHead>,
            download: DownloadBuffer
        ) {
            self.url = url
            self.upload = upload
            self.head = head
            self.download = download
        }

        func didSendRequestPart(task: HTTPClient.Task<Response>, _ part: IOData) {
            guard [.idle, .uploading].contains(state) && phase == .upload else {
                return
            }

            state = .uploading
            reference = .upload

            upload.append(.success(part.readableBytes))
        }

        func didSendRequest(task: HTTPClient.Task<Response>) {
            guard [.idle, .uploading].contains(state) && phase == .upload else {
                return
            }

            state = .uploading
            phase = .upload
            reference = .head

            upload.close()
        }

        func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
            guard
                ([.idle, .uploading].contains(state) && phase == .upload)
                    || [.head].contains(state) && phase == .download
            else {
                unexpectedStateOrPhase()
            }

            self.head.append(.success(ResponseHead(
                url: url,
                status: ResponseHead.Status(
                    code: head.status.code,
                    reason: head.status.reasonPhrase
                ),
                version: ResponseHead.Version(
                    minor: head.version.minor,
                    major: head.version.major
                ),
                headers: Headers(head.headers),
                isKeepAlive: head.isKeepAlive
            )))

            self.upload.close()
            self.head.close()

            state = .head
            phase = .download
            reference = .download

            return task.eventLoop.makeSucceededVoidFuture()
        }

        func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
            guard [.head, .downloading].contains(state) && phase == .download else {
                unexpectedStateOrPhase()
            }

            download.append(buffer)

            state = .downloading
            phase = .download
            reference = .download
            
            head.close()

            return task.eventLoop.makeSucceededVoidFuture()
        }

        func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
            guard [.head, .downloading, .end].contains(state) && phase == .download else {
                unexpectedStateOrPhase()
            }

            state = .end
            phase = .download
            reference = .lockout

            download.close()
            head.close()
            upload.close()
        }

        func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
            defer {
                state = .failure
                upload.close()
                head.close()
                download.close()
            }

            switch state {
            case .idle:
                guard reference <= .head else {
                    fallthrough
                }
                head.append(.failure(error))
            case .uploading:
                guard reference <= .upload else {
                    fallthrough
                }

                upload.append(.failure(error))
            case .head:
                guard reference <= .head else {
                    fallthrough
                }

                head.append(.failure(error))
            case .downloading:
                guard reference <= .download else {
                    fallthrough
                }

                download.failed(error)
            case .end, .failure:
                unexpectedStateOrPhase(error: error)
            }
        }
    }
}

extension Internals.ClientResponseReceiver {

    func unexpectedStateOrPhase(error: Error? = nil, line: UInt = #line) -> Never {
        Internals.Log.failure(
            .unexpectedStateOrPhase(
                state: state,
                phase: phase,
                error: error
            ),
            line: line
        )
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
