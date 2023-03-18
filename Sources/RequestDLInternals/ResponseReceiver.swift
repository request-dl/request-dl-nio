//
//  File.swift
//  
//
//  Created by Brenno on 17/03/23.
//

import Foundation
import AsyncHTTPClient

public class Stream<Value> {

    private enum State<Value> {
        case value(Value)
        case end(Value?)
        case failure(Error)

        var value: Value? {
            switch self {
            case .value(let value):
                return value
            case .end(let value):
                return value
            case .failure:
                return nil
            }
        }

        var isFailure: Bool {
            guard case .failure = self else {
                return false
            }

            return true
        }

        var isClosed: Bool {
            guard case .end = self else {
                return false
            }

            return true
        }
    }

    private var closure: ((State<Value>) -> Void)?
    private var state: State<[Value]>
    private let queue: OperationQueue

    init(queue: OperationQueue) {
        closure = nil
        state = .value([])
        self.queue = queue
    }

    private func post(_ state: State<Value>) {
        guard
            !self.state.isFailure && !self.state.isClosed,
            let values = self.state.value
        else { return }

        switch state {
        case .value(let value):
            guard let closure = closure else {
                self.state = .value(values + [value])
                return
            }

            for value in values + [value] {
                closure(.value(value))
            }

            self.state = .value([])
        case .end:
            self.state = .end(values.isEmpty ? nil : values)
            closure?(state)
        case .failure(let error):
            self.state = .failure(error)
            closure?(state)
        }
    }

    func append(_ value: Value) {
        post(.value(value))
    }

    func close() {
        post(.end(nil))
    }

    func failure(_ error: Error) {
        post(.failure(error))
    }

    private func attach(_ closure: @escaping (State<Value>) -> Void) {
        self.closure = closure

        switch self.state {
        case .value(let values):
            for value in values {
                closure(.value(value))
            }
            self.state = .value([])
        case .end(let values):
            if let values = values {
                for value in values {
                    closure(.value(value))
                }
            }
            closure(.end(nil))
        case .failure(let error):
            closure(.failure(error))
        }
    }

    func perform(_ block: @escaping () -> Void) {
        queue.addOperation(block)
    }

    func observe(_ closure: @escaping (Result<Value?, Error>) -> Void) {
        attach {
            switch $0 {
            case .value(let value):
                closure(.success(value))
            case .end(let value):
                if let value = value {
                    closure(.success(value))
                }
                closure(.success(nil))
            case .failure(let error):
                closure(.failure(error))
            }
        }
    }

    func makeAsyncStream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            observe {
                switch $0 {
                case .failure(let error):
                    continuation.finish(throwing: error)
                case .success(let value):
                    if let value = value {
                        continuation.yield(value)
                    } else {
                        continuation.finish(throwing: nil)
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

        state = .uploading
        phase = .upload
        upload.close()
    }

    func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
        guard
            ([.idle, .uploading].contains(state) && phase == .upload)
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

        state = .head
        phase = .download
        upload.close()

        return task.eventLoop.makeSucceededVoidFuture()
    }

    func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        guard [.head, .downloading].contains(state) && phase == .download else {
            fatalError()
        }

        state = .downloading
        phase = .download
        head.close()

        let promise = task.eventLoop.makePromise(of: Void.self)
        download.perform { [download] in
            for byte in buffer.readableBytesView {
                download.append(byte)
            }

            promise.succeed()
        }
        return promise.futureResult
    }

    func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
        guard [.head, .downloading, .end].contains(state) && phase == .download else {
            fatalError()
        }

        state = .end
        phase = .download
        download.close()
        head.close()
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
