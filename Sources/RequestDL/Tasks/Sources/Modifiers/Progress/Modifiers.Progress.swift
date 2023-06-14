/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension Modifiers {

    /// A modifier that allows tracking the progress of a request.
    public struct Progress<Input: Sendable, Output: Sendable>: RequestTaskModifier {

        let transform: @Sendable (Input) async throws -> Output

        init<Progress: UploadProgress>(_ progress: Progress) where Input == AsyncResponse, Output == TaskResult<AsyncBytes> {
            transform = {
                try await $0.collect(with: progress)
            }
        }

        init<Download: DownloadProgress>(_ progress: Download) where Input == TaskResult<AsyncBytes>, Output == TaskResult<Data> {
            transform = {
                try await .init(
                    head: $0.head,
                    payload: $0.payload.collect(with: progress)
                )
            }
        }

        init<Download: DownloadProgress>(_ progress: Download) where Input == AsyncBytes, Output == Data {
            transform = {
                try await $0.collect(with: progress)
            }
        }

        init<Upload: UploadProgress, Download: DownloadProgress>(
            upload: Upload,
            download: Download
        ) where Input == AsyncResponse, Output == TaskResult<Data> {
            transform = {
                let result = try await $0.collect(with: upload)
                return try await .init(
                    head: result.head,
                    payload: result.payload.collect(with: download)
                )
            }
        }

        /**
         Tracks the progress of a request.

         - Parameter task: The request task to modify.
         - Returns: The task result.
         - Throws: An error if the modification fails.
         */
        public func body(_ task: Content) async throws -> Output {
            try await transform(task.result())
        }
    }
}

// MARK: - RequestTask extensions

extension RequestTask<AsyncResponse> {

    /// Sets a progress tracking object for both upload and download.
    ///
    /// - Parameters:
    ///   - progress: The progress tracking object.
    /// - Returns: A modified request task with progress tracking.
    public func progress<Progress: RequestDL.Progress>(
        _ progress: Progress
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, TaskResult<Data>>> {
        self.progress(upload: progress, download: progress)
    }

    /// Sets separate progress tracking objects for upload and download.
    ///
    /// - Parameters:
    ///   - upload: The progress tracking object for upload.
    ///   - download: The progress tracking object for download.
    /// - Returns: A modified request task with progress tracking.
    public func progress<Upload: UploadProgress, Download: DownloadProgress>(
        upload: Upload,
        download: Download
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, TaskResult<Data>>> {
        modifier(Modifiers.Progress(
            upload: upload,
            download: download
        ))
    }

    /// Sets a progress tracking object for upload.
    ///
    /// - Parameters:
    ///   - upload: The progress tracking object for upload.
    /// - Returns: A modified request task with progress tracking.
    public func progress<Upload: UploadProgress>(
        upload: Upload
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, TaskResult<AsyncBytes>>> {
        modifier(Modifiers.Progress(upload))
    }
}

extension RequestTask<TaskResult<AsyncBytes>> {

    /// Sets a progress tracking object for download.
    ///
    /// - Parameters:
    ///   - download: The progress tracking object for download.
    /// - Returns: A modified request task with progress tracking.
    public func progress<Download: DownloadProgress>(
        download: Download
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, TaskResult<Data>>> {
        modifier(Modifiers.Progress(download))
    }
}

extension RequestTask<AsyncBytes> {

    /// Sets a progress tracking object for download.
    ///
    /// - Parameters:
    ///   - download: The progress tracking object for download.
    /// - Returns: A modified request task with progress tracking.
    public func progress<Download: DownloadProgress>(
        download: Download
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, Data>> {
        modifier(Modifiers.Progress(download))
    }
}

// MARK: - Deprecated

extension RequestTask<AsyncResponse> {

    @available(*, deprecated, renamed: "progress(upload:)")
    public func uploadProgress(
        _ upload: UploadProgress
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, TaskResult<AsyncBytes>>> {
        progress(upload: upload)
    }
}

extension RequestTask<TaskResult<AsyncBytes>> {

    @available(*, deprecated, renamed: "progress(download:)")
    public func downloadProgress(
        _ download: DownloadProgress
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, TaskResult<Data>>> {
        progress(download: download)
    }
}

extension RequestTask<AsyncBytes> {

    @available(*, deprecated, renamed: "progress(download:)")
    public func downloadProgress(
        _ download: DownloadProgress,
        length: Int? = nil
    ) -> ModifiedRequestTask<Modifiers.Progress<Element, Data>> {
        progress(download: download)
    }
}
