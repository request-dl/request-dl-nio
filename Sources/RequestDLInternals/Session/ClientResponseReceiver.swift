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
    let download: DataStream<ByteBuffer>
    private var bytesBuffer: ByteBuffer?

    var phase: Phase = .upload
    var state: State = .idle

    init(
        upload: DataStream<Int>,
        head: DataStream<ResponseHead>,
        download: DataStream<ByteBuffer>
    ) {
        self.upload = upload
        self.head = head
        self.download = download
    }

    func didSendRequestPart(task: HTTPClient.Task<Response>, _ part: IOData) {
        guard [.idle, .uploading].contains(state) && phase == .upload else {
            fatalError()
        }

        state = .uploading
        upload.append(.success(part.readableBytes))
    }

    func didSendRequest(task: HTTPClient.Task<Response>) {
        guard [.idle, .uploading].contains(state) && phase == .upload else {
            fatalError()
        }

        state = .uploading
        phase = .upload
        upload.close()
    }

    func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
        guard
            ([.idle, .uploading].contains(state) && phase == .upload)
                || [.head].contains(state) && phase == .download
        else { fatalError() }

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

        state = .head
        phase = .download
        upload.close()

        return task.eventLoop.makeSucceededVoidFuture()
    }

    func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        guard [.head, .downloading].contains(state) && phase == .download else {
            fatalError()
        }

        if var bytesBuffer {
            self.bytesBuffer = nil

            var buffer = buffer
            bytesBuffer.writeBuffer(&buffer)
            self.bytesBuffer = bytesBuffer

            download.append(.success(bytesBuffer))
        } else {
            bytesBuffer = buffer
        }

        state = .downloading
        phase = .download
        head.close()

        return task.eventLoop.makeSucceededVoidFuture()
    }

    func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
        guard [.head, .downloading, .end].contains(state) && phase == .download else {
            fatalError()
        }

        bytesBuffer = nil
        state = .end
        phase = .download
        download.close()
        head.close()
    }

    func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
        defer {
            bytesBuffer = nil
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
            download.append(.failure(error))
        case .end, .failure:
            fatalError()
        }
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
