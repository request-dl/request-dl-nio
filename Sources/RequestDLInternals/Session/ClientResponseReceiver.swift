/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

class ClientResponseReceiver: HTTPClientResponseDelegate {

    typealias Response = Void

    let upload: DataStream<Int>
    let head: DataStream<ResponseHead>
    var download: DownloadBuffer

    var phase: Phase = .upload
    var state: State = .idle

    init(
        upload: DataStream<Int>,
        head: DataStream<ResponseHead>,
        download: DownloadBuffer
    ) {
        self.upload = upload
        self.head = head
        self.download = download
    }

    func didSendRequestPart(task: HTTPClient.Task<Response>, _ part: IOData) {
        guard [.idle, .uploading].contains(state) && phase == .upload else {
            return
        }

        state = .uploading
        upload.append(.success(part.readableBytes))
    }

    func didSendRequest(task: HTTPClient.Task<Response>) {
        guard [.idle, .uploading].contains(state) && phase == .upload else {
            return
        }

        state = .uploading
        phase = .upload
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

        return task.eventLoop.makeSucceededVoidFuture()
    }

    func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        guard [.head, .downloading].contains(state) && phase == .download else {
            unexpectedStateOrPhase()
        }

        download.append(buffer)

        state = .downloading
        phase = .download
        head.close()

        return task.eventLoop.makeSucceededVoidFuture()
    }

    func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
        guard [.head, .downloading, .end].contains(state) && phase == .download else {
            unexpectedStateOrPhase()
        }

        state = .end
        phase = .download
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
            head.append(.failure(error))
        case .uploading:
            upload.append(.failure(error))
        case .head:
            head.append(.failure(error))
        case .downloading:
            download.failed(error)
        case .end, .failure:
            fatalError()
        }
    }
}

extension ClientResponseReceiver {
    
    func unexpectedStateOrPhase(_ line: UInt = #line) -> Never {
        Log.debug(
            """
            state = \(state)
            phase = \(phase)
            """,
            line: line
        )

        Log.failure(
            """
            An invalid state or phase has been detected, which could \
            cause unexpected behavior within the application.

            If this was not an intentional change, please report this \
            issue by opening a bug report 🔎.
            """,
            line: line
        )
    }
}

extension ClientResponseReceiver {

    enum State {
        case idle
        case uploading
        case head
        case downloading
        case end
        case failure
    }
}

extension ClientResponseReceiver {

    enum Phase {
        case upload
        case download
    }
}
