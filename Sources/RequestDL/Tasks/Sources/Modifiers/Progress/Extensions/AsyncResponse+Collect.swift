/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

extension AsyncResponse {

    func collect<Upload: UploadProgress>(with progress: Upload) async throws -> TaskResult<AsyncBytes> {
        for try await step in self {
            switch step {
            case .upload(let step):
                log(receivedStep: step)
                progress.upload(step.chunkSize, totalSize: step.totalSize)
            case .download(let step):
                log(responseHead: step.head)
                return .init(head: step.head, payload: step.bytes)
            }
        }

        try Task.checkCancellation()
        throw RequestFailureError()
    }

    func collect() async throws -> TaskResult<AsyncBytes> {
        for try await step in self {
            switch step {
            case .upload(let step):
                log(receivedStep: step)
            case .download(let step):
                log(responseHead: step.head)
                return .init(
                    head: step.head,
                    payload: step.bytes
                )
            }
        }

        try Task.checkCancellation()
        throw RequestFailureError()
    }

    func log(receivedStep step: UploadStep) {
        logger?.log(level: .debug, "Uploaded \(step.chunkSize) bytes", additionalMetadata: [
            "chunk_size": .stringConvertible(step.chunkSize),
            "total_size": .stringConvertible(step.totalSize),
        ])
    }

    func log(responseHead: ResponseHead) {
        logger?.log(level: .debug, "Received response", additionalMetadata: [
            "status": .stringConvertible(responseHead.status),
            "version": .stringConvertible(responseHead.version),
            "keep_alive": .stringConvertible(responseHead.isKeepAlive)
        ])
    }
}
