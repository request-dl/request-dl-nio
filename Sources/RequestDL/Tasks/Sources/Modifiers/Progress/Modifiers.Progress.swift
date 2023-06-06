/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension Modifiers {

    public struct Progress<Input: Sendable, Output: Sendable>: RequestTaskModifier {

        // MARK: - Private properties

        private let process: @Sendable (Input) async throws -> Output

        // MARK: - Inits

        fileprivate init(
            _ progress: RequestDL.Progress
        ) where Input == AsyncResponse, Output == TaskResult<Data> {
            self.process = {
                let downloadPart = try await Self.upload(progress, content: $0)

                let data = try await Self.download(
                    progress,
                    length: progress.contentLengthHeaderKey
                        .flatMap { downloadPart.head.headers[$0] }
                        .flatMap { $0.lazy.compactMap(Int.init).first },
                    content: downloadPart.payload
                )

                return .init(head: downloadPart.head, payload: data)
            }
        }

        fileprivate init(
            _ progress: UploadProgress
        ) where Input == AsyncResponse, Output == TaskResult<AsyncBytes> {
            self.process = {
                try await Self.upload(progress, content: $0)
            }
        }

        fileprivate init(
            _ progress: DownloadProgress
        ) where Input == TaskResult<AsyncBytes>, Output == TaskResult<Data> {
            self.process = { downloadPart in
                let data = try await Self.download(
                    progress,
                    length: progress.contentLengthHeaderKey
                        .flatMap { downloadPart.head.headers[$0] }
                        .flatMap { $0.lazy.compactMap(Int.init).first },
                    content: downloadPart.payload
                )

                return .init(head: downloadPart.head, payload: data)
            }
        }

        fileprivate init(
            _ progress: DownloadProgress,
            length: Int?
        ) where Input == AsyncBytes, Output == Data {
            self.process = { bytes in
                try await Self.download(
                    progress,
                    length: length,
                    content: bytes
                )
            }
        }

        // MARK: - Public methods

        public func body(_ task: Content) async throws -> Output {
            try await process(task.result())
        }

        // MARK: - Private static methods

        private static func upload(
            _ progress: RequestDL.UploadProgress,
            content: AsyncResponse
        ) async throws -> TaskResult<AsyncBytes> {

            for try await step in content {
                switch step {
                case .upload(let bytesLength):
                    progress.upload(bytesLength)
                case .download(let head, let bytes):
                    return .init(head: head, payload: bytes)
                }
            }

            Internals.Log.failure(
                .missingStagesOfRequest(content)
            )
        }

        private static func download(
            _ progress: RequestDL.DownloadProgress,
            length: Int?,
            content: AsyncBytes
        ) async throws -> Data {
            var receivedData = Data()

            for try await data in content {
                progress.download(data, length: length)
                receivedData.append(data)
            }

            return receivedData
        }
    }
}

// MARK: - RequestTask extensions

extension RequestTask<AsyncResponse> {

    public func progress(
        _ progress: Progress
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, TaskResult<Data>>> {
        modifier(Modifiers.Progress(progress))
    }

    public func uploadProgress(
        _ upload: UploadProgress
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, TaskResult<AsyncBytes>>> {
        modifier(Modifiers.Progress(upload))
    }
}

extension RequestTask<TaskResult<AsyncBytes>> {

    public func downloadProgress(
        _ download: DownloadProgress
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, TaskResult<Data>>> {
        modifier(Modifiers.Progress(download))
    }
}

extension RequestTask<AsyncBytes> {

    public func downloadProgress(
        _ download: DownloadProgress,
        length: Int? = nil
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, Data>> {
        modifier(Modifiers.Progress(download, length: length))
    }
}
