//
// See LICENSE for this package's licensing information.
//

import NIOCore

extension Internals {

    package struct AsyncResponse: Sendable, AsyncSequence {

        package struct Iterator: Sendable, AsyncIteratorProtocol {

            // MARK: - Internal properties

            package let logger: Internals.TaskLogger?
            package let uploadingBytes: Int
            package let upload: AsyncStream<Int>.AsyncIterator?
            package let decompressionDispatch: Internals.ManualDecompressionDispatch
            package let download:
                (
                    head: Internals.AsyncStream<Internals.ResponseHead>,
                    bytes: Internals.AsyncStream<Internals.DataBuffer>
                )?

            // MARK: - Internal methods

            package mutating func next() async throws -> Element? {
                if var upload = upload, let chunkSize = try await upload.next() {
                    self = .init(
                        logger: logger,
                        uploadingBytes: uploadingBytes,
                        upload: upload,
                        decompressionDispatch: decompressionDispatch,
                        download: download
                    )

                    return .upload(
                        .init(
                            chunkSize: chunkSize,
                            totalSize: uploadingBytes
                        )
                    )
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
                    decompressionDispatch: decompressionDispatch,
                    download: nil
                )

                return try lastHead.map { head in
                    let totalSize = head.headerValues(named: "Content-Length")
                        .lazy
                        .flatMap { $0.split(separator: ",") }
                        .map { $0.trimming(where: \.isWhitespace) }
                        .compactMap { Int($0) }
                        .max()

                    let resolvedStream = try decompressionDispatch.resolvedStream(for: head, source: data)

                    return .download(
                        DownloadStep(
                            head: head,
                            bytes: AsyncBytes(
                                logger: logger,
                                totalSize: totalSize ?? .zero,
                                stream: resolvedStream
                            )
                        )
                    )
                }
            }
        }

        package typealias Element = ResponseStep

        // MARK: - Internal properties

        package let logger: Internals.TaskLogger?

        // MARK: - Private properties

        private let uploadingBytes: Int
        private let upload: Internals.AsyncStream<Int>
        private let decompressionDispatch: Internals.ManualDecompressionDispatch
        private let head: Internals.AsyncStream<Internals.ResponseHead>
        private let download: Internals.AsyncStream<Internals.DataBuffer>

        // MARK: - Inits

        package init(
            logger: Internals.TaskLogger?,
            uploadingBytes: Int,
            upload: Internals.AsyncStream<Int>,
            decompressionDispatch: Internals.ManualDecompressionDispatch,
            head: Internals.AsyncStream<Internals.ResponseHead>,
            download: Internals.AsyncStream<Internals.DataBuffer>
        ) {
            self.logger = logger
            self.uploadingBytes = uploadingBytes
            self.upload = upload
            self.decompressionDispatch = decompressionDispatch
            self.head = head
            self.download = download
        }

        // MARK: - Internal methods

        package func makeAsyncIterator() -> Iterator {
            Iterator(
                logger: logger,
                uploadingBytes: uploadingBytes,
                upload: upload.makeAsyncIterator(),
                decompressionDispatch: decompressionDispatch,
                download: (head, download)
            )
        }
    }
}
