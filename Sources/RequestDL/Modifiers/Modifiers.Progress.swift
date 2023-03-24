/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import _RequestDLExtensions

extension Modifiers {

    public struct Progress<Content: Task, Output>: TaskModifier {

        private let process: (Content.Element) async throws -> Output

        fileprivate init(
            _ progress: RequestDL.Progress
        ) where Content.Element == AsyncResponse, Output == TaskResult<Data> {
            self.process = {
                let downloadPart = try await Self.upload(progress, content: $0)

                let data = try await Self.download(
                    progress,
                    length: progress.contentLengthHeaderKey
                        .flatMap { downloadPart.head.headers[$0] }
                        .flatMap(Int.init),
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
                        .flatMap(Int.init),
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

        public func task(_ task: Content) async throws -> Output {
            try await process(task.result())
        }
    }
}

extension Modifiers.Progress {

    fileprivate static func upload(_ progress: RequestDL.UploadProgress, content: AsyncResponse) async throws -> TaskResult<AsyncBytes> {

        for try await step in content {
            switch step {
            case .upload(let bytesLength):
                progress.upload(bytesLength)
            case .download(let head, let bytes):
                return .init(head: head, payload: bytes)
            }
        }

        fatalError()
    }

    fileprivate static func download(
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

extension Task<AsyncResponse> {

    public func progress(
        _ progres: Progress
    ) -> ModifiedTask<Modifiers.Progress<Self, TaskResult<Data>>> {
        modify(Modifiers.Progress(progres))
    }

    public func progress(
        upload: UploadProgress
    ) -> ModifiedTask<Modifiers.Progress<Self, TaskResult<AsyncBytes>>> {
        modify(Modifiers.Progress(upload))
    }
}

extension Task<TaskResult<AsyncBytes>> {

    public func progress(
        download: DownloadProgress
    ) -> ModifiedTask<Modifiers.Progress<Self, TaskResult<Data>>> {
        modify(Modifiers.Progress(download))
    }
}

extension Task<AsyncBytes> {

    public func progress(
        download: DownloadProgress,
        length: Int? = nil
    ) -> ModifiedTask<Modifiers.Progress<Self, Data>> {
        modify(Modifiers.Progress(download, length: length))
    }
}
