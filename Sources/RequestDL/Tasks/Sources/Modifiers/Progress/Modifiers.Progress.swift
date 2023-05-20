/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    public struct Progress<Content: Task, Output: Sendable>: TaskModifier {

        // MARK: - Private properties

        private let process: @Sendable (Content.Element) async throws -> Output

        // MARK: - Inits

        fileprivate init(
            _ progress: RequestDL.Progress
        ) where Content.Element == AsyncResponse, Output == TaskResult<Data> {
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
        ) where Content.Element == AsyncResponse, Output == TaskResult<AsyncBytes> {
            self.process = {
                try await Self.upload(progress, content: $0)
            }
        }

        fileprivate init(
            _ progress: DownloadProgress
        ) where Content.Element == TaskResult<AsyncBytes>, Output == TaskResult<Data> {
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
        ) where Content.Element == AsyncBytes, Output == Data {
            self.process = { bytes in
                try await Self.download(
                    progress,
                    length: length,
                    content: bytes
                )
            }
        }

        // MARK: - Public methods

        public func task(_ task: Content) async throws -> Output {
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

// MARK: - Task extensions

extension Task<AsyncResponse> {

    public func progress(
        _ progress: Progress
    ) -> ModifiedTask<Modifiers.Progress<Self, TaskResult<Data>>> {
        modify(Modifiers.Progress(progress))
    }

    public func uploadProgress(
        _ upload: UploadProgress
    ) -> ModifiedTask<Modifiers.Progress<Self, TaskResult<AsyncBytes>>> {
        modify(Modifiers.Progress(upload))
    }
}

extension Task<TaskResult<AsyncBytes>> {

    public func downloadProgress(
        _ download: DownloadProgress
    ) -> ModifiedTask<Modifiers.Progress<Self, TaskResult<Data>>> {
        modify(Modifiers.Progress(download))
    }
}

extension Task<AsyncBytes> {

    public func downloadProgress(
        _ download: DownloadProgress,
        length: Int? = nil
    ) -> ModifiedTask<Modifiers.Progress<Self, Data>> {
        modify(Modifiers.Progress(download, length: length))
    }
}
