/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension AsyncBytes {

    func collect<Download: DownloadProgress>(with progress: Download) async throws -> Data {
        var data = Data()
        data.reserveCapacity(totalSize)

        for try await slice in self {
            progress.download(slice, totalSize: totalSize)
            data.append(slice)
        }

        return data
    }

    func collect() async throws -> Data {
        var data = Data()
        data.reserveCapacity(totalSize)

        for try await bytes in self {
            data.append(bytes)
        }

        return data
    }
}
