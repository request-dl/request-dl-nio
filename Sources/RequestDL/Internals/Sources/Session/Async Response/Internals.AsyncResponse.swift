/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct AsyncResponse: Sendable, AsyncSequence {

        struct Iterator: Sendable, AsyncIteratorProtocol {

            // MARK: - Internal properties

            let logger: Internals.TaskLogger?
            let uploadingBytes: Int
            let upload: AsyncStream<Int>.AsyncIterator?
            let download: (
                head: Internals.AsyncStream<Internals.ResponseHead>,
                bytes: Internals.AsyncStream<Internals.DataBuffer>
            )?

            // MARK: - Internal methods

            mutating func next() async throws -> Element? {
                if var upload = upload, let chunkSize = try await upload.next() {
                    self = .init(
                        logger: logger,
                        uploadingBytes: uploadingBytes,
                        upload: upload,
                        download: download
                    )

                    return .upload(.init(
                        chunkSize: chunkSize,
                        totalSize: uploadingBytes
                    ))
                }

                guard let (heads, data) = download else {
                    return nil
                }

                var lastHead: Internals.ResponseHead?

                for try await head in heads {
                    lastHead = head
                }

                self = .init(
                    logger: logger,
                    uploadingBytes: uploadingBytes,
                    upload: nil,
                    download: nil
                )

                return lastHead.map { head in
                    let totalSize = head.headers
                        .components(name: "Content-Length")?
                        .compactMap(Int.init)
                        .max()

                    return .download(DownloadStep(
                        head: head,
                        bytes: AsyncBytes(
                            logger: logger,
                            totalSize: totalSize ?? .zero,
                            stream: data
                        )
                    ))
                }
            }
        }

        typealias Element = ResponseStep

        // MARK: - Internal properties

        let logger: Internals.TaskLogger?

        // MARK: - Private properties

        private let uploadingBytes: Int
        private let upload: Internals.AsyncStream<Int>
        private let head: Internals.AsyncStream<Internals.ResponseHead>
        private let download: Internals.AsyncStream<Internals.DataBuffer>

        // MARK: - Inits

        init(
            logger: Internals.TaskLogger?,
            uploadingBytes: Int,
            upload: Internals.AsyncStream<Int>,
            head: Internals.AsyncStream<Internals.ResponseHead>,
            download: Internals.AsyncStream<Internals.DataBuffer>
        ) {
            self.logger = logger
            self.uploadingBytes = uploadingBytes
            self.upload = upload
            self.head = head
            self.download = download
        }

        // MARK: - Internal methods

        func makeAsyncIterator() -> Iterator {
            Iterator(
                logger: logger,
                uploadingBytes: uploadingBytes,
                upload: upload.makeAsyncIterator(),
                download: (head, download)
            )
        }
    }
}
