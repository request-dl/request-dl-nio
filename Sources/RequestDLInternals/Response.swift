/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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

    public typealias Element = Result

    private let upload: AsyncThrowingStream<Int, Error>
    private let head: AsyncThrowingStream<ResponseHead, Error>
    private let download: Stream<UInt8>

    init(
        upload: Stream<Int>,
        head: Stream<ResponseHead>,
        download: Stream<UInt8>
    ) {
        self.upload = upload.makeAsyncStream()
        self.head = head.makeAsyncStream()
        self.download = download
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(
            upload: upload.makeAsyncIterator(),
            download: (
                head.makeAsyncIterator(),
                download
            )
        )
    }
}

extension AsyncResponse {

    public struct Iterator: AsyncIteratorProtocol {

        public typealias Element = AsyncResponse.Result

        let upload: AsyncThrowingStream<Int, Error>.Iterator?
        let download: (
            AsyncThrowingStream<ResponseHead, Error>.Iterator,
            Stream<UInt8>
        )?

        public mutating func next() async throws -> AsyncResponse.Result? {
            if var upload = upload, let part = try await upload.next() {
                self = .init(
                    upload: upload,
                    download: download
                )

                return .upload(part)
            } else if let download = download {
                var headStream = download.0
                let download = download.1

                var lastHead: ResponseHead?

                while let head = try await headStream.next() {
                    lastHead = head
                }

                self = .init(
                    upload: nil,
                    download: nil
                )

                return lastHead.map {
                    .download($0, .init(download))
                }
            } else {
                return nil
            }
        }
    }
}

extension AsyncResponse {

    public enum Result {
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
