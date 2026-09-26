//
// See LICENSE for this package's licensing information.
//

import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension AsyncBytes {

    /// A ceiling on the up-front allocation `reserveCapacity` below performs, independent of
    /// however large `totalSize` claims to be.
    ///
    /// `totalSize` comes verbatim from the response's `Content-Length` header — attacker- or
    /// server-controlled, not validated against how many bytes actually arrive. Passing it to
    /// `reserveCapacity` directly lets a response claiming an enormous length (a malicious
    /// endpoint, a compromised CDN edge, or a MITM without pinning) force an immediate
    /// multi-gigabyte allocation before a single byte is read, which is its own denial of
    /// service (jetsam kill on iOS/watchOS, OOM kill on Linux) regardless of how much data
    /// actually follows. Capping the reservation only changes how much `Data` pre-allocates —
    /// `append` below still grows it to fit the real byte count either way.
    private static let maximumReservedCapacity = 16 << 20  // 16 MiB

    func collect<Download: DownloadProgress>(with progress: Download) async throws -> Data {
        var data = Data()
        data.reserveCapacity(Swift.min(totalSize, Self.maximumReservedCapacity))

        for try await slice in self {
            log(receivedBytes: slice)
            progress.download(slice, totalSize: totalSize)
            data.append(slice)
        }

        // The underlying stream's own iterator ends the sequence cleanly (no error) when *this*
        // task is the one that got cancelled, the same "cancellation transparent" contract
        // `AsyncResponse.collect()` already guards against. Without this check, a body read cut
        // short by the caller's own cancellation looks identical to one that ended because the
        // server closed the connection normally, and `data` -- silently truncated -- is returned
        // as if it were the complete response.
        try Task.checkCancellation()

        log(data: data)
        return data
    }

    func collect() async throws -> Data {
        var data = Data()
        data.reserveCapacity(Swift.min(totalSize, Self.maximumReservedCapacity))

        for try await bytes in self {
            log(receivedBytes: bytes)
            data.append(bytes)
        }

        // See the identical check in the overload above: without it, this task's own
        // cancellation ends the stream with no error, and a truncated body comes back as if it
        // were a complete, successful response.
        try Task.checkCancellation()

        log(data: data)
        return data
    }

    private func log(receivedBytes: Data) {
        logger?.log(
            level: .debug,
            "Downloaded \(receivedBytes.count) bytes",
            additionalMetadata: [
                "raw_bytes": .stringConvertible(receivedBytes),
                "total_size": .stringConvertible(totalSize),
            ]
        )
    }

    private func log(data: Data) {
        logger?.log(
            level: .debug,
            "Data fetched: \(data.count) bytes",
            additionalMetadata: [
                "raw_bytes": .string(data.safeLogDescription())
            ]
        )
    }
}
