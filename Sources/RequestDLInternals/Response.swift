/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public typealias BytesStream = Stream<UInt8>

public enum ResponsePart {
    case upload(Int)
    case download(ResponseHead, BytesStream)
}

public typealias ResponseStream = Stream<ResponsePart>

func reduce(
    queue: OperationQueue,
    upload: Stream<Int>,
    head: Stream<ResponseHead>,
    download: BytesStream
) -> ResponseStream {
    let stream = ResponseStream(queue: queue)

    upload.observe {
        switch $0 {
        case .failure(let error):
            stream.failure(error)
            stream.close()
        case .success(let part):
            if let part = part {
                stream.append(.upload(part))
            } else {
                var receivedHead: ResponseHead?

                head.observe {
                    switch $0 {
                    case .failure(let error):
                        stream.failure(error)
                        stream.close()
                    case .success(let head):
                        if let head = head {
                            receivedHead = head
                        } else if let head = receivedHead {
                            stream.append(.download(head, download))
                            stream.close()
                        } else {
                            fatalError()
                        }
                    }
                }
            }
        }
    }

    return stream
}

public struct AsyncStream<Element>: AsyncSequence {

    private let stream: AsyncThrowingStream<Element, Error>

    init(_ stream: Stream<Element>) {
        self.stream = stream.makeAsyncStream()
    }

    public func makeAsyncIterator() -> Iterator<Element> {
        .init(iterator: stream.makeAsyncIterator())
    }
}

extension AsyncStream {

    public struct Iterator<Element>: AsyncIteratorProtocol {

        private(set) var iterator: AsyncThrowingStream<Element, Error>.AsyncIterator

        public mutating func next() async throws -> Element? {
            try await iterator.next()
        }
    }
}

public typealias AsyncBytes = AsyncStream<UInt8>

public struct AsyncResponse: AsyncSequence {

    private let response: AsyncThrowingStream<ResponsePart, Error>

    init(response: Stream<ResponsePart>) {
        self.response = response.makeAsyncStream()
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(response: response.makeAsyncIterator())
    }
}

extension AsyncResponse {

    public struct Iterator: AsyncIteratorProtocol {

        public typealias Element = AsyncResponse.Element

        var response: AsyncThrowingStream<ResponsePart, Error>.Iterator

        public mutating func next() async throws -> Element? {
            switch try await response.next() {
            case .upload(let part):
                return .upload(part)
            case .download(let response, let bytes):
                return .download(response, .init(bytes))
            case .none:
                return nil
            }
        }
    }
}

extension AsyncResponse {

    public enum Element {
        case upload(Int)
        case download(ResponseHead, AsyncBytes)
    }
}

public struct ResponseHead {
    public let status: Status
    public let version: Version
    public let headers: Headers
    public let isKeepAlive: Bool
}

extension ResponseHead {

    public struct Version {
        public let minor: Int
        public let major: Int
    }

    public struct Status {
        public let code: UInt
        public let reason: String
    }
}
