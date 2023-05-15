/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct AsyncResponse: Sendable, AsyncSequence {

        struct Iterator: AsyncIteratorProtocol {

            // MARK: - Internal properties

            let upload: AsyncStream<Int>.AsyncIterator?
            let download: (
                head: Internals.AsyncStream<Internals.ResponseHead>,
                bytes: Internals.AsyncStream<Internals.DataBuffer>
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

        typealias Element = Response

        // MARK: - Private properties

        private let upload: Internals.AsyncStream<Int>
        private let head: Internals.AsyncStream<Internals.ResponseHead>
        private let download: Internals.AsyncStream<Internals.DataBuffer>

        // MARK: - Inits

        init(
            upload: Internals.AsyncStream<Int>,
            head: Internals.AsyncStream<Internals.ResponseHead>,
            download: Internals.AsyncStream<Internals.DataBuffer>
        ) {
            self.upload = upload
            self.head = head
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
