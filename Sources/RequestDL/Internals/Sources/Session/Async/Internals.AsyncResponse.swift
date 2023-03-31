/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

struct AsyncResponse: AsyncSequence {

    typealias Element = Response

    private let upload: AsyncThrowingStream<Int, Error>
    private let head: AsyncThrowingStream<ResponseHead, Error>
    private let download: DataStream<DataBuffer>

    init(
        upload: DataStream<Int>,
        head: DataStream<ResponseHead>,
        download: DataStream<DataBuffer>
    ) {
        self.upload = upload.asyncStream()
        self.head = head.asyncStream()
        self.download = download
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(
            upload: upload.makeAsyncIterator(),
            download: (head, download)
        )
    }
}

extension AsyncResponse {

    struct Iterator: AsyncIteratorProtocol {

        let upload: AsyncThrowingStream<Int, Error>.AsyncIterator?
        let download: (
            head: AsyncThrowingStream<ResponseHead, Error>,
            bytes: DataStream<DataBuffer>
        )?

        mutating func next() async throws -> Element? {
            if var upload = upload, let part = try await upload.next() {
                self = .init(
                    upload: upload,
                    download: download
                )
                return .upload(part)
            }

            guard let (heads, data) = download else {
                return nil
            }

            var lastHead: ResponseHead?

            for try await head in heads {
                lastHead = head
            }

            self = .init(upload: nil, download: nil)
            return lastHead.map {
                .download($0, .init(data))
            }
        }
    }
}
