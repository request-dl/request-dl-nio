/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension AsyncResponse {

    func collect<Upload: UploadProgress>(with progress: Upload) async throws -> TaskResult<AsyncBytes> {
        for try await step in self {
            switch step {
            case .upload(let step):
                progress.upload(step.chunkSize, totalSize: step.totalSize)
            case .download(let step):
                return .init(head: step.head, payload: step.bytes)
            }
        }

        try Task.checkCancellation()
        throw RequestFailureError()
    }

    func collect() async throws -> TaskResult<AsyncBytes> {
        for try await step in self {
            if case .download(let step) = step {
                return .init(
                    head: step.head,
                    payload: step.bytes
                )
            }
        }

        try Task.checkCancellation()
        throw RequestFailureError()
    }
}
