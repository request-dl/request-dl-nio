/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension Modifiers {

    @available(*, deprecated, renamed: "Convert")
    public struct IgnoresProgress<Input: Sendable, Output: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let process: @Sendable (Input) async throws -> Output

        // MARK: - Inits

        fileprivate init() where Input == AsyncResponse, Output == TaskResult<Data> {
            self.process = {
                let downloadPart = try await Self.ignoresUpload($0)
                let data = try await Self.ignoresDownload(downloadPart.payload)
                return .init(head: downloadPart.head, payload: data)
            }
        }

        fileprivate init() where Input == AsyncResponse, Output == TaskResult<AsyncBytes> {
            self.process = {
                try await Self.ignoresUpload($0)
            }
        }

        fileprivate init() where Input == TaskResult<AsyncBytes>, Output == TaskResult<Data> {
            self.process = { downloadPart in
                let data = try await Self.ignoresDownload(downloadPart.payload)
                return .init(head: downloadPart.head, payload: data)
            }
        }

        fileprivate init() where Input == AsyncBytes, Output == Data {
            self.process = { bytes in
                try await Self.ignoresDownload(bytes)
            }
        }

        // MARK: - Public methods

        public func body(_ task: Content) async throws -> Output {
            try await process(task.result())
        }

        // MARK: - Private static methods

        private static func ignoresUpload(_ content: AsyncResponse) async throws -> TaskResult<AsyncBytes> {

            for try await step in content {
                switch step {
                case .upload:
                    break
                case .download(let step):
                    return .init(head: step.head, payload: step.bytes)
                }
            }

            try Task.checkCancellation()
            throw RequestFailureError()
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

// MARK: - RequestTask extension

extension RequestTask {

    @available(*, deprecated, renamed: "collectData")
    public func ignoresProgress() -> ModifiedRequestTask<Modifiers.IgnoresProgress<Element, TaskResult<Data>>>
    where Element == AsyncResponse {
        modifier(Modifiers.IgnoresProgress())
    }

    @available(*, deprecated, renamed: "collectBytes")
    public func ignoresUploadProgress() -> ModifiedRequestTask<Modifiers.IgnoresProgress<Element, TaskResult<AsyncBytes>>>
    where Element == AsyncResponse {
        modifier(Modifiers.IgnoresProgress())
    }

    @available(*, deprecated, renamed: "collectData")
    public func ignoresDownloadProgress() -> ModifiedRequestTask<Modifiers.IgnoresProgress<Element, TaskResult<Data>>>
    where Element == TaskResult<AsyncBytes> {
        modifier(Modifiers.IgnoresProgress())
    }

    @available(*, deprecated, renamed: "collectData")
    public func ignoresDownloadProgress() -> ModifiedRequestTask<Modifiers.IgnoresProgress<Element, Data>>
    where Element == AsyncBytes {
        modifier(Modifiers.IgnoresProgress())
    }
}
