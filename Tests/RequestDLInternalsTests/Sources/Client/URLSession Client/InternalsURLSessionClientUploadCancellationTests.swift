//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Foundation
@_spi(Testing) import SwiftAsyncStream
import Testing

@_spi(Testing) @testable import RequestDLInternals
@testable import RequestDLTestSupport

/// A request whose body was being written out when the caller was cancelled must not be sent.
///
/// Writing the body (`Internals.URLSessionUploadFile`) does not look at cancellation, and the exchange
/// that follows is a `Task` of its own, which does not inherit it from the caller. Without a check
/// right after the body is written, a body whose source ignores cancellation (a file read, a user's
/// own sequence) would finish and the request would go out all the same, even though the caller had
/// been told it was cancelled.
struct InternalsURLSessionClientUploadCancellationTests {

    /// Holds the first element of the body back until the test lets it go, ignoring cancellation:
    /// the source a caller cannot interrupt.
    private final class Gate: @unchecked Sendable {

        private let lock = Lock()
        private var continuation: UnsafeContinuation<Void, Never>?
        private var isReleased = false

        var isParked: Bool {
            lock.withLock { continuation != nil }
        }

        func park() async {
            await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
                let resume = lock.withLock { () -> Bool in
                    guard !isReleased else {
                        return true
                    }

                    self.continuation = continuation
                    return false
                }

                if resume {
                    continuation.resume()
                }
            }
        }

        func release() {
            let continuation = lock.withLock { () -> UnsafeContinuation<Void, Never>? in
                isReleased = true
                defer { self.continuation = nil }
                return self.continuation
            }

            continuation?.resume()
        }
    }

    private struct GatedBody: AsyncSequence, Sendable {

        typealias Element = Internals.Bytes

        struct AsyncIterator: AsyncIteratorProtocol {
            let gate: Gate
            var remaining: Int
            var isFirst = true

            mutating func next() async -> Internals.Bytes? {
                if isFirst {
                    isFirst = false
                    await gate.park()
                }

                guard remaining > 0 else {
                    return nil
                }

                let count = Swift.min(1_048_576, remaining)
                remaining -= count

                return Internals.Bytes(Data(repeating: 0x5A, count: count))
            }
        }

        let gate: Gate
        let size: Int

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(gate: gate, remaining: size)
        }
    }

    /// Files `Internals.URLSessionUploadFile` spilled a body of exactly `size` bytes to.
    private static func spilledFiles(ofSize size: Int) -> [URL] {
        let directory = FileManager.default.temporaryDirectory

        let files =
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

        return files.filter {
            $0.pathExtension == "buffer"
                && (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) == size
        }
    }

    /// 1 KiB stays in memory. The other is past `Internals.URLSessionUploadFile.inMemoryThreshold`
    /// (not a multiple of a megabyte, so no other test's temporary file has its size), and spills to
    /// a temporary file the cancelled request has to remove.
    @Test(arguments: [1_024, Internals.URLSessionUploadFile.inMemoryThreshold + 12_345])
    func execute_whenCancelledWhileTheBodyIsBeingWritten_throwsWithoutSendingIt(size: Int) async throws {
        try await withTransferServer(.init(length: 16)) { server in
            // Given: a request whose body is stuck at its first element, holding the only slot.
            let client = try Internals.URLSessionClient(
                configuration: .ephemeral,
                maximumConcurrentConnections: 1
            )

            let semaphore = try #require(client.connectionSemaphoreForTesting)
            let gate = Gate()

            var request = try URLRequest(url: #require(URL(string: "http://127.0.0.1:\(server.port)/upload")))
            request.httpMethod = "POST"

            let upload = _Concurrency.Task {
                try await client.execute(
                    request: request,
                    streaming: GatedBody(gate: gate, size: size),
                    readingMode: .length(1_024),
                    uploadingBytes: size,
                    decompression: .disabled,
                    cache: nil,
                    logger: nil
                )
            }

            try await eventually(timeout: 30) { gate.isParked }
            #expect(semaphore.availablePermits == 0)

            // When: cancelled there, and the body then finishes, as one that ignores cancellation does.
            upload.cancel()
            gate.release()

            // Then: the call throws instead of handing back a request that is about to go out.
            await #expect(throws: CancellationError.self) {
                _ = try await upload.value
            }

            // And everything it held is back, before it threw.
            #expect(semaphore.availablePermits == 1)
            #expect(!client.isRunning)

            // (A body that stayed in memory left no file to look for, and 1 KiB is a size other tests'
            // own temporary files have.)
            if size > Internals.URLSessionUploadFile.inMemoryThreshold {
                #expect(Self.spilledFiles(ofSize: size).isEmpty)
            }

            #expect(server.acceptedConnections == 0)
        }
    }
}

#endif
