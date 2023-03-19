/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

public struct Request {

    public var url: String
    public var method: String?
    public var headers: Headers
    public var body: Body?

    public init(url: String) {
        self.url = url
        self.method = nil
        self.headers = .init()
        self.body = nil
    }
}

extension Request {

    func build(_ eventLoop: EventLoop) throws -> HTTPClient.Request {
        try HTTPClient.Request(
            url: url,
            method: method.map { .init(rawValue: $0) } ?? .GET,
            headers: .init(headers.build()),
            body: body?.build(eventLoop)
        )
    }
}

import NIOCore

extension Request {

    public struct Body {

        private let length: Int?
        private let iterator: DataSequence.Iterator

        public init(
            length: Int?,
            bufferSize: Int = 1024,
            streams: [() -> InputStream]
        ) {
            precondition(streams.first != nil)
            self.length = length
            self.iterator = DataSequence(streams, bufferSize: bufferSize).makeIterator()
        }

        func build(_ eventLoop: EventLoop) -> HTTPClient.Body {
            .stream(length: length) { stream in
                write(
                    iterator: iterator,
                    stream: stream,
                    eventLoop: eventLoop
                )
            }
        }
    }
}

struct DataSequence: Sequence {

    typealias Element = () throws -> ByteBuffer

    private let inputs: [() -> InputStream]
    private let bufferSize: Int

    init(
        _ inputs: [() -> InputStream],
        bufferSize: Int
    ) {
        self.inputs = inputs
        self.bufferSize = bufferSize
    }

    func makeIterator() -> Iterator {
        Iterator(
            readingInput: inputs.first?(),
            inputs: inputs.dropFirst(),
            bufferSize: bufferSize
        )
    }
}

extension DataSequence {

    class Iterator: IteratorProtocol {

        typealias Element = () throws -> ByteBuffer

        var readingInput: InputStream?
        var inputs: Array<() -> InputStream>.SubSequence
        let bufferSize: Int

        init(
            readingInput: InputStream?,
            inputs: Array<() -> InputStream>.SubSequence,
            bufferSize: Int
        ) {
            readingInput?.open()
            self.readingInput = readingInput
            self.inputs = inputs
            self.bufferSize = bufferSize
        }

        func next() -> Element? {
            guard let readingInput = readingInput else {
                return nil
            }

            guard readingInput.hasBytesAvailable else {
                readingInput.close()

                self.readingInput = inputs.first?()
                self.inputs = inputs.dropFirst()

                self.readingInput?.open()
                return self.next()
            }

            var buffer = [UInt8](repeating: 0, count: bufferSize)
            let bytesRead = readingInput.read(&buffer, maxLength: bufferSize)

            if let error = readingInput.streamError {
                readingInput.close()
                return { throw error }
            }

            return { .init(bytes: buffer[0 ..< bytesRead]) }
        }

        deinit {
            readingInput?.close()
        }
    }
}

extension Request.Body {

    func write(
        iterator: DataSequence.Iterator,
        stream: HTTPClient.Body.StreamWriter,
        eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        do {
            guard let item = try iterator.next()?() else {
                return eventLoop.makeSucceededVoidFuture()
            }

            return stream.write(.byteBuffer(item)).flatMap {
                write(
                    iterator: iterator,
                    stream: stream,
                    eventLoop: eventLoop
                )
            }
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }
}
