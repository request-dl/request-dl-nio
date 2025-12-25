/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

extension AsyncBytes {

    func collect<Download: DownloadProgress>(with progress: Download) async throws -> Data {
        var data = Data()
        data.reserveCapacity(totalSize)

        for try await slice in self {
            log(receivedBytes: slice)
            progress.download(slice, totalSize: totalSize)
            data.append(slice)
        }

        log(data: data)
        return data
    }

    func collect() async throws -> Data {
        var data = Data()
        data.reserveCapacity(totalSize)

        for try await bytes in self {
            log(receivedBytes: bytes)
            data.append(bytes)
        }

        log(data: data)
        return data
    }

    private func log(receivedBytes: Data) {
        logger?.log(level: .debug, "Downloaded \(receivedBytes.count) bytes", additionalMetadata: [
            "raw_bytes": .stringConvertible(receivedBytes),
            "total_size": .stringConvertible(totalSize)
        ])
    }

    private func log(data: Data) {
        logger?.log(level: .debug, "Data fetched: \(data.count) bytes", additionalMetadata: [
            "raw_bytes": .string(data.safeLogDescription())
        ])
    }
}
