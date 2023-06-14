/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct AsyncResponse: Sendable, AsyncSequence {

        struct Iterator: AsyncIteratorProtocol {

            // MARK: - Internal properties

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
                    uploadingBytes: uploadingBytes,
                    upload: nil,
                    download: nil
                )

                return lastHead.map {
                    let totalSize = $0.headers["Content-Length"]?
                        .reduce([]) { $0 + $1.split(separator: ",") }
                        .lazy
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .compactMap(Int.init)
                        .max()

                    return .download(DownloadStep(
                        head: $0,
                        bytes: AsyncBytes(
                            totalSize: totalSize ?? .zero,
                            stream: data
                        )
                    ))
                }
            }
        }

        typealias Element = ResponseStep

        // MARK: - Private properties

        private let uploadingBytes: Int
        private let upload: Internals.AsyncStream<Int>
        private let head: Internals.AsyncStream<Internals.ResponseHead>
        private let download: Internals.AsyncStream<Internals.DataBuffer>

        // MARK: - Inits

        init(
            uploadingBytes: Int,
            upload: Internals.AsyncStream<Int>,
            head: Internals.AsyncStream<Internals.ResponseHead>,
            download: Internals.AsyncStream<Internals.DataBuffer>
        ) {
            self.uploadingBytes = uploadingBytes
            self.upload = upload
            self.head = head
            self.download = download
        }

        // MARK: - Internal methods

        func makeAsyncIterator() -> Iterator {
            Iterator(
                uploadingBytes: uploadingBytes,
                upload: upload.makeAsyncIterator(),
                download: (head, download)
            )
        }
    }
}
