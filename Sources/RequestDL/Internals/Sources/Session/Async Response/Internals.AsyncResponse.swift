/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct AsyncResponse: Sendable, AsyncSequence {

        typealias Element = Response

        // MARK: - Private properties

        private let upload: AsyncThrowingStream<Int, Error>
        private let head: AsyncThrowingStream<Internals.ResponseHead, Error>
        private let download: Internals.DataStream<Internals.DataBuffer>

        // MARK: - Inits

        init(
            upload: Internals.DataStream<Int>,
            head: Internals.DataStream<Internals.ResponseHead>,
            download: Internals.DataStream<Internals.DataBuffer>
        ) {
            self.upload = upload.asyncStream()
            self.head = head.asyncStream()
            self.download = download
        }

        // MARK: - Internal methods

        func makeAsyncIterator() -> Iterator {
            Iterator(
                upload: upload.makeAsyncIterator(),
                download: (head, download)
            )
        }
    }
}

extension Internals.AsyncResponse {

    struct Iterator: AsyncIteratorProtocol {

        // MARK: - Internal properties

        let upload: AsyncThrowingStream<Int, Error>.AsyncIterator?
        let download: (
            head: AsyncThrowingStream<Internals.ResponseHead, Error>,
            bytes: Internals.DataStream<Internals.DataBuffer>
        )?

        // MARK: - Internal methods

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

            var lastHead: Internals.ResponseHead?

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
