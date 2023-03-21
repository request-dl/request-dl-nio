/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

public struct AsyncResponse: AsyncSequence {

    public typealias Element = Response

    private let upload: AsyncThrowingStream<Int, Error>
    private let head: AsyncThrowingStream<ResponseHead, Error>
    private let download: DataStream<ByteBuffer>

    init(
        upload: DataStream<Int>,
        head: DataStream<ResponseHead>,
        download: DataStream<ByteBuffer>
    ) {
        self.upload = upload.asyncStream()
        self.head = head.asyncStream()
        self.download = download
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(
            upload: upload.makeAsyncIterator(),
            download: (head, download)
        )
    }
}

extension AsyncResponse {

    public struct Iterator: AsyncIteratorProtocol {

        public typealias Element = AsyncResponse.Element

        let upload: AsyncThrowingStream<Int, Error>.AsyncIterator?
        let download: (
            head: AsyncThrowingStream<ResponseHead, Error>,
            bytes: DataStream<ByteBuffer>
        )?

        public mutating func next() async throws -> Element? {
            if var upload = upload, let part = try await upload.next() {
                self = .init(
                    upload: upload,
                    download: download
                )
                return .upload(part)
            }

            guard let (heads, bytes) = download else {
                return nil
            }

            var lastHead: ResponseHead?

            for try await head in heads {
                lastHead = head
            }

            self = .init(upload: nil, download: nil)
            return lastHead.map {
                .download($0, .init(bytes))
            }
        }
    }
}
