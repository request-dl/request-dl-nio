/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    public struct IgnoresProgress<Content: Task, Output>: TaskModifier {

        let process: (Content.Element) async throws -> Output

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

        public func task(_ task: Content) async throws -> Output {
            try await process(task.result())
        }
    }
}

extension Modifiers.IgnoresProgress {

    fileprivate static func ignoresUpload(_ content: AsyncResponse) async throws -> TaskResult<AsyncBytes> {

        for try await step in content {
            switch step {
            case .upload:
                break
            case .download(let head, let bytes):
                return .init(head: head, payload: bytes)
            }
        }

        Internals.Log.failure(
            """
            An error occurred while attempting to iterate through an \
            asynchronous sequence representing the stages of a request.

            The absence of a complete request was detected, as the loop \
            terminated prematurely without encountering an upload or download \
            step.

            Please, open a bug report 🔎
            """
        )
    }

    fileprivate static func ignoresDownload(_ content: AsyncBytes) async throws -> Data {
        var receivedData = Data()

        for try await data in content {
            receivedData.append(data)
        }

        return receivedData
    }
}

extension Task<AsyncResponse> {

    public func ignoresProgress() -> ModifiedTask<Modifiers.IgnoresProgress<Self, TaskResult<Data>>> {
        modify(Modifiers.IgnoresProgress())
    }

    public func ignoresUploadProgress() -> ModifiedTask<Modifiers.IgnoresProgress<Self, TaskResult<AsyncBytes>>> {
        modify(Modifiers.IgnoresProgress())
    }
}

extension Task<TaskResult<AsyncBytes>> {

    public func ignoresDownloadProgress() -> ModifiedTask<Modifiers.IgnoresProgress<Self, TaskResult<Data>>> {
        modify(Modifiers.IgnoresProgress())
    }
}

extension Task<AsyncBytes> {

    public func ignoresDownloadProgress() -> ModifiedTask<Modifiers.IgnoresProgress<Self, Data>> {
        modify(Modifiers.IgnoresProgress())
    }
}
