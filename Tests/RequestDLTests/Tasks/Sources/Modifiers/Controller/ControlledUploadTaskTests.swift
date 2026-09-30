//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

/// `.controller(_:)` on an ``UploadTask``, through the public API, on every executor.
///
/// What can still reach the server once suspended is whatever the client's kernel already
/// accepted, so the suspension is triggered by the server itself, from its own thread, at an
/// exact byte early in the body, and the server reads slower than loopback would
/// (`uploadReadDelay`). See `InternalsTransferControlUploadTests` for why: triggered from the
/// test's own task instead, under load, the whole body can already be in the socket buffers.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct ControlledUploadTaskTests {

    /// One below and one above `Internals.URLSessionUploadFile.inMemoryThreshold`, so `.urlSession`
    /// pumps the smaller from memory and the larger from a file it spills to.
    private static let sizes = [6 * 1_048_576, 24 * 1_048_576]

    private typealias Executor = TransferTestExecutor

    private static func body(size: Int) -> Data {
        var data = Data()
        data.reserveCapacity(size)

        var position = 0
        while position < size {
            let count = min(65_536, size - position)
            data.append(contentsOf: TransferServer.uploadBody(from: position, count: count))
            position += count
        }

        return data
    }

    private static func upload(
        to server: TransferServer,
        executor: Executor,
        payload: some Property
    ) -> UploadTask<some Property> {
        UploadTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/upload")
            RequestMethod(.put)
            executor.session
            payload
        }
    }

    // MARK: - Tests

    /// Suspended mid-body: nothing more reaches the server beyond what its kernel had already
    /// accepted, for as long as the controller stays suspended, and after resuming the server
    /// receives exactly the body, every byte once and in order.
    @Test(arguments: Executor.allCases, sizes)
    private func suspendMidUpload_stopsTheBodyUntilResumed(_ executor: Executor, size: Int) async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let controller = RequestController()
            let suspendedAt = LockedValueBox<Int?>(nil)

            server.uploadReadDelay = 2_000
            server.onUploadProgress = { received in
                guard received >= 262_144, suspendedAt.withLockedValue({ $0 == nil }) else {
                    return
                }

                suspendedAt.withLockedValue { $0 = received }
                controller.suspend()
            }

            let task = Self.upload(to: server, executor: executor, payload: Payload(data: Self.body(size: size)))
                .collectData()
                .extractPayload()
                .controller(controller)

            let running = _Concurrency.Task { try await task.result() }

            try await eventually(timeout: 30) { suspendedAt.withLockedValue { $0 != nil } }
            server.onUploadProgress = nil

            let receivedAtSuspension = try #require(suspendedAt.withLockedValue { $0 })
            let stalledAt = try await server.settled { server.uploadBytesReceived }

            // Then: what was already in the socket buffers still arrives, and nothing more.
            #expect(stalledAt < size)
            #expect(stalledAt - receivedAtSuspension <= 4_718_592)

            try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
            #expect(server.uploadBytesReceived == stalledAt)

            // When
            controller.resume()
            _ = try await running.value

            // Then
            let request = try #require(server.requests.first)
            #expect(server.requests.count == 1)
            #expect(request.bodyLength == size)
            #expect(request.isBodyIntact)
            #expect(request.isBodyComplete)
        }
    }

    /// The same, from a file: the body a request streams from disk instead of holding in memory.
    @Test(arguments: Executor.allCases)
    private func suspendMidUpload_ofAFile_stopsTheBodyUntilResumed(_ executor: Executor) async throws {
        let size = 24 * 1_048_576

        try await withTemporaryFileURL("controlled-upload-\(executor.testDescription)") { fileURL in
            try Self.body(size: size).write(to: fileURL)

            try await withTransferServer(.init(length: 1_024)) { server in
                // Given
                let controller = RequestController()
                let suspendedAt = LockedValueBox<Int?>(nil)

                server.uploadReadDelay = 2_000
                server.onUploadProgress = { received in
                    guard received >= 262_144, suspendedAt.withLockedValue({ $0 == nil }) else {
                        return
                    }

                    suspendedAt.withLockedValue { $0 = received }
                    controller.suspend()
                }

                let task = Self.upload(
                    to: server,
                    executor: executor,
                    payload: Payload(url: fileURL, contentType: .octetStream)
                )
                .collectData()
                .extractPayload()
                .controller(controller)

                let running = _Concurrency.Task { try await task.result() }

                try await eventually(timeout: 30) { suspendedAt.withLockedValue { $0 != nil } }
                server.onUploadProgress = nil

                let stalledAt = try await server.settled { server.uploadBytesReceived }

                // Then
                #expect(stalledAt < size)

                try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                #expect(server.uploadBytesReceived == stalledAt)

                // When
                controller.resume()
                _ = try await running.value

                // Then
                let request = try #require(server.requests.first)
                #expect(request.bodyLength == size)
                #expect(request.isBodyIntact)
                #expect(request.isBodyComplete)
            }
        }
    }

    /// Suspended before the request starts: not a single body byte reaches the server until
    /// resumed, and the whole body arrives after.
    @Test(arguments: Executor.allCases)
    private func startedWhileSuspended_sendsNoBodyUntilResumed(_ executor: Executor) async throws {
        let size = 2 * 1_048_576

        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let controller = RequestController()
            controller.suspend()

            let task = Self.upload(to: server, executor: executor, payload: Payload(data: Self.body(size: size)))
                .collectData()
                .extractPayload()
                .controller(controller)

            // When
            let running = _Concurrency.Task { try await task.result() }

            try await _Concurrency.Task.sleep(nanoseconds: 1_500_000_000)

            // Then
            #expect(server.uploadBytesReceived == 0)

            // When
            controller.resume()
            _ = try await running.value

            // Then
            let request = try #require(server.requests.first)
            #expect(request.bodyLength == size)
            #expect(request.isBodyIntact)
            #expect(request.isBodyComplete)
        }
    }
}
