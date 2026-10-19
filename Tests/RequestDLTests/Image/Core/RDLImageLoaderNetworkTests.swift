//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

#if canImport(UIKit) || canImport(AppKit)

/// A load cancelled while its image is on the wire, against a real server: the other tests of
/// `RDLImageLoader` use a stub in place of the request, so none of them shows that cancelling a
/// call stops the download itself.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct RDLImageLoaderNetworkTests {

    private static let length = 128 * 1_048_576
    private static let heldAt = 1_048_576

    /// Held by the server after the first MiB of 128, so the download is in flight when the call
    /// is cancelled. Once the hold is released a download that is still wanted goes on to the end
    /// (`isBodyComplete`), and one that was cancelled finds the connection closed.
    @Test
    func cancellingTheOnlyCaller_stopsTheDownloadOnTheWire() async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            server.holdsDownloadAt = Self.heldAt

            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/resource"))
            let loader = RDLImageLoader()
            let load = Task { try await loader.load(url: url) }

            try await eventually(timeout: 120) { server.bodyBytesWritten >= Self.heldAt }
            try await eventually(timeout: 120) { await loader.waiterCountForTesting(id: url.absoluteString) == 1 }

            // When: the only call waiting for it goes away, as a row scrolled off screen does.
            load.cancel()
            try await eventually(timeout: 120) { await loader.waiterCountForTesting(id: url.absoluteString) == 0 }

            await #expect(throws: CancellationError.self) {
                _ = try await load.value
            }

            // And the server is let go.
            server.holdsDownloadAt = nil
            try await awaitRecordedRequests(server)

            // Then: the body did not reach the client, which had closed the connection.
            let request = try #require(server.requests.first)

            #expect(request.isBodyComplete == false)
            #expect(request.bodyLength < Self.length)
        }
    }
}

#endif
