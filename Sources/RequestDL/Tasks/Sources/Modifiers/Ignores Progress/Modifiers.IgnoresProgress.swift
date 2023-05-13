/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    public struct IgnoresProgress<Content: Task, Output: Sendable>: TaskModifier {

        // MARK: - Internal properties

        let process: @Sendable (Content.Element) async throws -> Output

        // MARK: - Inits

        fileprivate init() where Content.Element == AsyncResponse, Output == TaskResult<Data> {
            self.process = {
                let downloadPart = try await Self.ignoresUpload($0)
                let data = try await Self.ignoresDownload(downloadPart.payload)
                return .init(head: downloadPart.head, payload: data)
            }
        }

        fileprivate init() where Content.Element == AsyncResponse, Output == TaskResult<AsyncBytes> {
            self.process = {
                try await Self.ignoresUpload($0)
            }
        }

        fileprivate init() where Content.Element == TaskResult<AsyncBytes>, Output == TaskResult<Data> {
            self.process = { downloadPart in
                let data = try await Self.ignoresDownload(downloadPart.payload)
                return .init(head: downloadPart.head, payload: data)
            }
        }

        fileprivate init() where Content.Element == AsyncBytes, Output == Data {
            self.process = { bytes in
                try await Self.ignoresDownload(bytes)
            }
        }

        // MARK: - Public methods

        public func task(_ task: Content) async throws -> Output {
            try await process(task.result())
        }

        // MARK: - Private static methods

        private static func ignoresUpload(_ content: AsyncResponse) async throws -> TaskResult<AsyncBytes> {

            for try await step in content {
                switch step {
                case .upload:
                    break
                case .download(let head, let bytes):
                    return .init(head: head, payload: bytes)
                }
            }

            Internals.Log.failure(
                .missingStagesOfRequest(content)
            )
        }

        private static func ignoresDownload(_ content: AsyncBytes) async throws -> Data {
            var receivedData = Data()

            for try await data in content {
                receivedData.append(data)
            }

            return receivedData
        }
    }
}

// MARK: - Task extension

extension Task {

    public func ignoresProgress() -> ModifiedTask<Modifiers.IgnoresProgress<Self, TaskResult<Data>>>
    where Element == AsyncResponse {
        modify(Modifiers.IgnoresProgress())
    }

    public func ignoresUploadProgress() -> ModifiedTask<Modifiers.IgnoresProgress<Self, TaskResult<AsyncBytes>>>
    where Element == AsyncResponse {
        modify(Modifiers.IgnoresProgress())
    }

    public func ignoresDownloadProgress() -> ModifiedTask<Modifiers.IgnoresProgress<Self, TaskResult<Data>>>
    where Element == TaskResult<AsyncBytes> {
        modify(Modifiers.IgnoresProgress())
    }

    public func ignoresDownloadProgress() -> ModifiedTask<Modifiers.IgnoresProgress<Self, Data>>
    where Element == AsyncBytes {
        modify(Modifiers.IgnoresProgress())
    }
}
