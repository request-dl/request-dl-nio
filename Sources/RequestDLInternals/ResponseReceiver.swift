//
//  File.swift
//  
//
//  Created by Brenno on 17/03/23.
//

import Foundation
import AsyncHTTPClient

@globalActor
actor StreamActor {
    static var shared = StreamActor()
}

@StreamActor
class Stream<Value> {

    private enum State<Value> {
        case value(Value)
        case end
        case failure(Error)
    }

    private var closure: ((State<Value>) -> Void)?
    private var queue: State<[Value]>

    init() {
        closure = nil
        queue = .value([])
    }

    private func post(_ state: State<Value>) {
        guard case .value(let values) = queue else {
            return
        }

        switch state {
        case .value(let value):
            guard let closure = closure else {
                queue = .value(values + [value])
                return
            }

            for value in values + [value] {
                closure(.value(value))
            }

            queue = .value([])
        case .end:
            queue = .end
            closure?(state)
        case .failure(let error):
            queue = .failure(error)
            closure?(state)
        }
    }

    nonisolated func append(_ value: Value) {
        Task { @StreamActor in
            post(.value(value))
        }
    }

    nonisolated func close() {
        Task { @StreamActor in
            post(.end)
        }
    }

    nonisolated func failure(_ error: Error) {
        Task { @StreamActor in
            post(.failure(error))
        }
    }

    private func attach(_ closure: @escaping (State<Value>) -> Void) {
        self.closure = closure

        switch queue {
        case .value(let values):
            for value in values {
                closure(.value(value))
            }
            queue = .value([])
        case .end:
            closure(.end)
        case .failure(let error):
            closure(.failure(error))
        }
    }

    nonisolated func makeAsyncStream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            Task { @StreamActor in
                attach {
                    switch $0 {
                    case .value(let value):
                        continuation.yield(value)
                    case .end:
                        continuation.finish(throwing: nil)
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}

import NIOCore
import NIOHTTP1

class StreamResponse: HTTPClientResponseDelegate {

    typealias Response = Void

    let upload: Stream<Int>
    let head: Stream<ResponseHead>
    let download: Stream<UInt8>

    var phase: Phase = .upload
    var state: State = .idle

    init(
        upload: Stream<Int>,
        head: Stream<ResponseHead>,
        download: Stream<UInt8>
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
        upload.append(part.readableBytes)
    }

    func didSendRequest(task: HTTPClient.Task<Response>) {
        guard [.idle, .uploading].contains(state) && phase == .upload else {
            fatalError()
        }

        state = .head
        phase = .download
        upload.close()
    }

    func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
        guard
            ([.idle].contains(state) && phase == .upload)
                || [.head].contains(state) && phase == .download
        else { fatalError() }

        self.head.append(ResponseHead(
            status: ResponseHead.Status(
                code: head.status.code,
                reason: head.status.reasonPhrase
            ),
            version: ResponseHead.Version(
                minor: head.version.minor,
                major: head.version.major
            ),
            headers: Headers(head.headers.map { $0 }),
            isKeepAlive: head.isKeepAlive
        ))

        state = .downloading
        phase = .download
        upload.close()

        return task.eventLoop.makeSucceededVoidFuture()
    }

    func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        guard [.downloading].contains(state) && phase == .download else {
            fatalError()
        }

        state = .downloading
        phase = .download

        for byte in buffer.readableBytesView {
            download.append(byte)
        }

        return task.eventLoop.makeSucceededVoidFuture()
    }

    func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
        guard [.downloading].contains(state) && phase == .download else {
            fatalError()
        }

        state = .end
        phase = .download
        download.close()
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
            head.failure(error)
        case .uploading:
            upload.failure(error)
        case .head:
            head.failure(error)
        case .downloading:
            download.failure(error)
        case .end, .failure:
            fatalError()
        }
    }
}

extension StreamResponse {

    enum State {
        case idle
        case uploading
        case head
        case downloading
        case end
        case failure
    }
}

extension StreamResponse {

    enum Phase {
        case upload
        case download
    }
}
