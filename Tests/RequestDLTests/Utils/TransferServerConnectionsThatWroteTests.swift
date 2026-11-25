//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// ``TransferServer/connectionsThatWrote`` is what a test waits on before it samples a server that
/// is meant to be quiet: the byte count alone is a sum over every connection, so the first one to
/// write makes it positive while the others may not have begun.
struct TransferServerConnectionsThatWroteTests {

    // The server writes a body 16 KiB at a time and holds at a piece boundary, so a request is
    // still in flight (its connection busy, a second request cannot reuse it) once it is held.
    private static let heldAt = 16_384

    private func get(from server: TransferServer) -> _Concurrency.Task<Void, Error> {
        _Concurrency.Task {
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
            }
            .result()
        }
    }

    /// The case a byte count cannot tell apart: one request has written, the second has not even
    /// been made. `bodyBytesWritten > 0` is already true; waiting for it was the old, too weak,
    /// condition.
    @Test
    func whenOnlyOneOfTwoConnectionsWrote_theByteCountIsPositiveAndTheCountOfWritersIsOne() async throws {
        try await withTransferServer(.init(length: Self.heldAt * 4)) { server in
            // Given
            server.holdsDownloadAt = Self.heldAt

            // When
            let first = get(from: server)
            try await eventually(timeout: 30) { server.connectionsThatWrote == 1 }

            // Then: the old condition is met with one connection.
            #expect(server.bodyBytesWritten > 0)

            // The second one has not been made, so nothing makes the count move.
            try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
            #expect(server.connectionsThatWrote == 1)
            #expect(server.acceptedConnections == 1)

            // When
            let second = get(from: server)
            try await eventually(timeout: 30) { server.connectionsThatWrote == 2 }

            // Then
            #expect(server.acceptedConnections == 2)

            server.holdsDownloadAt = nil
            try await first.value
            try await second.value
        }
    }

    /// A connection that wrote twice is still one.
    @Test
    func whenAConnectionWritesMoreThanOnce_itCountsOnce() async throws {
        try await withTransferServer(.init(length: 1_048_576)) { server in
            // When
            try await get(from: server).value

            // Then
            #expect(server.bodyBytesWritten >= 1_048_576)
            #expect(server.connectionsThatWrote == 1)
        }
    }
}
