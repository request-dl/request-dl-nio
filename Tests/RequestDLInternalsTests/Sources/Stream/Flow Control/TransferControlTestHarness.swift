//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(NIOCore)
import AsyncHTTPClient
import NIOCore
#endif

#if canImport(Darwin)
import Darwin
import Foundation
#elseif canImport(FoundationEssentials)
import FoundationEssentials
import Glibc
#else
import Foundation
import Glibc
#endif

/// The executors a transfer-control test runs against, every one available in this build. Tests
/// are parameterized over it, so each guarantee is checked the same way, by the same test body,
/// on both executors: parity is what's under test as much as the mechanism itself.
enum TransferExecutor: String, Sendable, CaseIterable, CustomTestStringConvertible {
    #if canImport(NIOCore)
    case nio
    #endif

    #if canImport(Darwin)
    case urlSession
    #endif

    var testDescription: String {
        rawValue
    }
}

/// Starts downloads and uploads against a ``TransferServer`` on one executor, through the same
/// `Internals` entry points the `RequestExecutingClient` conformances use.
struct TransferHarness: Sendable {

    struct Download: Sendable {
        let task: SessionTask
        let step: Internals.DownloadStep

        /// The client (and, for `.nio`, the session) behind the request, kept alive for as long
        /// as the test holds this.
        fileprivate let owner: any Sendable
    }

    let executor: TransferExecutor

    /// Seconds without progress before the *client* gives up: `timeoutIntervalForRequest` on
    /// `.urlSession`, the read timeout on `.nio`. `nil` leaves each executor's default (60 s on
    /// `.urlSession`, none on `.nio`).
    var idleTimeout: Double?

    init(_ executor: TransferExecutor, idleTimeout: Double? = nil) {
        self.executor = executor
        self.idleTimeout = idleTimeout
    }

    // MARK: - Downloads

    /// Starts a `GET` and returns once the response head is in, before any of the body is read.
    func download(
        from server: TransferServer,
        readingMode: Internals.DownloadStep.ReadingMode = .length(65_536),
        flowControl: Internals.FlowControlWindow = .init(),
        transferControl: Internals.TransferControl?
    ) async throws -> Download {
        let url = "http://127.0.0.1:\(server.port)/resource"
        let task: SessionTask
        let owner: any Sendable

        switch executor {
        #if canImport(NIOCore)
        case .nio:
            let (session, client) = try await nioClient()
            owner = [session, client] as [any Sendable]

            task = try await session.execute(
                client: client,
                request: try HTTPClient.Request(url: url),
                url: url,
                readingMode: readingMode,
                uploadingBytes: .zero,
                decompression: .disabled,
                cache: nil,
                logger: nil,
                flowControl: flowControl,
                transferControl: transferControl
            )
        #endif

        #if canImport(Darwin)
        case .urlSession:
            let client = try urlSessionClient()
            owner = client

            task = try await client.execute(
                request: URLRequest(url: try #require(URL(string: url))),
                readingMode: readingMode,
                uploadingBytes: .zero,
                decompression: .disabled,
                cache: nil,
                logger: nil,
                flowControl: flowControl,
                transferControl: transferControl
            )
        #endif
        }

        for try await step in task.response {
            if case .download(let download) = step {
                return Download(task: task, step: download, owner: owner)
            }
        }

        throw AnyError()
    }

    // MARK: - Uploads

    /// Starts a `PUT` of `size` bytes of ``TransferServer/uploadByte(at:)``, streamed in 64 KiB
    /// pieces the way `RequestBody` streams its own.
    ///
    /// - Returns: The task, and the client behind it (to keep alive).
    func upload(
        to server: TransferServer,
        size: Int,
        path: String = "/upload",
        transferControl: Internals.TransferControl?
    ) async throws -> (task: SessionTask, owner: any Sendable) {
        let url = "http://127.0.0.1:\(server.port)\(path)"
        let body = PatternUploadBody(size: size)

        switch executor {
        #if canImport(NIOCore)
        case .nio:
            let (session, client) = try await nioClient()
            let eventLoop = client.eventLoopGroup.any()
            let gate = transferControl?.gate

            let request = try HTTPClient.Request(
                url: url,
                method: .PUT,
                body: .stream(length: size) { writer in
                    eventLoop.makeFutureWithTask {
                        var iterator = Internals.StreamWriterSequence(
                            writer: writer,
                            body: body,
                            gate: gate
                        ).makeAsyncIterator()

                        while let write = try await iterator.next() {
                            try await write.get()
                        }
                    }
                }
            )

            let task = try await session.execute(
                client: client,
                request: request,
                url: url,
                readingMode: .length(65_536),
                uploadingBytes: size,
                decompression: .disabled,
                cache: nil,
                logger: nil,
                transferControl: transferControl
            )

            return (task, [session, client] as [any Sendable])
        #endif

        #if canImport(Darwin)
        case .urlSession:
            let client = try urlSessionClient()
            var request = URLRequest(url: try #require(URL(string: url)))
            request.httpMethod = "PUT"

            let task = try await client.execute(
                request: request,
                streaming: body,
                readingMode: .length(65_536),
                uploadingBytes: size,
                decompression: .disabled,
                cache: nil,
                logger: nil,
                transferControl: transferControl
            )

            return (task, client)
        #endif
        }
    }

    // MARK: - Clients

    #if canImport(NIOCore)
    private func nioClient() async throws -> (Internals.Session, Internals.Client) {
        var configuration = Internals.Session.Configuration()

        // Above the most transfers any test runs at once (the stress test's twelve), so the pool's
        // default of eight never makes one wait, past its acquisition timeout on a slow runner,
        // for a connection another suspended transfer is holding.
        configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = 32

        if let idleTimeout {
            configuration.timeout.read = Int64(idleTimeout * 1_000_000_000)
        }

        let session = Internals.Session(
            provider: .identified("com.requestdl.tests.transfer-control", numberOfThreads: 2),
            configuration: configuration
        )

        return (session, try await session.client())
    }
    #endif

    #if canImport(Darwin)
    private func urlSessionClient() throws -> Internals.URLSessionClient {
        let configuration = URLSessionConfiguration.ephemeral

        if let idleTimeout {
            configuration.timeoutIntervalForRequest = idleTimeout
        }

        return try Internals.URLSessionClient(configuration: configuration)
    }
    #endif
}

// MARK: - Bodies

/// ``TransferServer/uploadByte(at:)`` as an upload body, in 64 KiB pieces. Re-iterable, so a
/// resend (a redirect) sends the same bytes again.
struct PatternUploadBody: AsyncSequence, Sendable {

    typealias Element = Internals.Bytes

    struct AsyncIterator: AsyncIteratorProtocol {
        let size: Int
        var position = 0

        mutating func next() async -> Internals.Bytes? {
            guard position < size else {
                return nil
            }

            let count = Swift.min(65_536, size - position)
            let bytes = TransferServer.uploadBody(from: position, count: count)
            position += count

            return Internals.Bytes(Data(bytes))
        }
    }

    let size: Int

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(size: size)
    }
}

/// Checks a downloaded body against ``TransferServer``'s resource incrementally, so large bodies
/// are never held by the test itself. Remembers where the first wrong byte was, if any.
struct ResourceVerifier: Sendable {

    let seed: Int
    private(set) var position = 0
    private(set) var firstMismatch: Int?

    var isIntact: Bool {
        firstMismatch == nil
    }

    init(seed: Int = 0) {
        self.seed = seed
    }

    mutating func consume(_ data: Data) {
        var offset = data.startIndex

        while offset < data.endIndex {
            let length = min(TransferServer.maximumPiece, data.endIndex - offset)
            let expected = TransferServer.body(from: position, count: length, seed: seed)

            if firstMismatch == nil, !data[offset..<offset + length].elementsEqual(expected) {
                firstMismatch = position
            }

            offset += length
            position += length
        }
    }
}

/// Waits until `server` has recorded at least `count` requests.
///
/// A ``TransferServer`` records a request once it is done with it, which can be after the client
/// already has its response (or has seen its connection end). Read straight away, the list can
/// still be missing the last one under load, so anything asserting on it after the client's side
/// of the exchange finished waits for it first.
func awaitRecordedRequests(_ server: TransferServer, atLeast count: Int = 1) async throws {
    try await eventually(timeout: 30) { server.requests.count >= count }
}

/// Prints a measured value when `REQUESTDL_TRANSFER_MEASUREMENTS` is set, so the numbers the
/// assertions bound can be looked at directly without making every run noisy.
func reportMeasurement(_ label: String, _ value: CustomStringConvertible) {
    if getenv("REQUESTDL_TRANSFER_MEASUREMENTS") != nil {
        print("[transfer-measurement] \(label): \(value)")
    }
}

extension TransferExecutor {

    /// Whether `error` is this executor's own client-side idle timeout.
    func isIdleTimeout(_ error: (any Error)?) -> Bool {
        switch self {
        #if canImport(NIOCore)
        case .nio:
            return (error as? HTTPClientError) == .readTimeout
        #endif

        #if canImport(Darwin)
        case .urlSession:
            return (error as? URLError)?.code == .timedOut
        #endif
        }
    }
}

/// How reading a body ended.
enum ReadOutcome: Sendable, Equatable {
    case finished
    case failed(String)
}

extension ReadOutcome {

    var isFailure: Bool {
        if case .failed = self {
            return true
        }

        return false
    }
}

/// Reads `bytes` to its end with `verifier`, or until it fails, within `timeout` seconds.
func readToEnd(
    _ bytes: Internals.AsyncBytes,
    verifier: ResourceVerifier,
    timeout: Double = 60
) async throws -> (ResourceVerifier, ReadOutcome, (any Error)?) {
    let result = try await completing(within: timeout) { () -> (ResourceVerifier, ReadOutcome, ErrorBox) in
        var verifier = verifier

        do {
            for try await chunk in bytes {
                verifier.consume(chunk)
            }

            return (verifier, .finished, ErrorBox(nil))
        } catch {
            return (verifier, .failed(String(describing: type(of: error))), ErrorBox(error))
        }
    }

    return (result.0, result.1, result.2.error)
}

/// Carries an error across `completing(within:)`'s `Sendable` boundary.
struct ErrorBox: @unchecked Sendable {
    let error: (any Error)?

    init(_ error: (any Error)?) {
        self.error = error
    }
}

/// Reads a body in the background as fast as it arrives -- an eager app, so whatever holds the
/// transfer back is the suspension, never the reader -- checking it as it goes.
final class BackgroundReader: Sendable {

    private struct State {
        var verifier: ResourceVerifier
        var outcome: ReadOutcome?
        var error: ErrorBox = .init(nil)
    }

    private let state: LockedValueBox<State>
    private let task: _Concurrency.Task<Void, Never>

    var position: Int {
        state.withLockedValue { $0.verifier.position }
    }

    var verifier: ResourceVerifier {
        state.withLockedValue { $0.verifier }
    }

    /// `nil` while still reading.
    var outcome: ReadOutcome? {
        state.withLockedValue { $0.outcome }
    }

    var error: (any Error)? {
        state.withLockedValue { $0.error.error }
    }

    init(_ bytes: Internals.AsyncBytes, seed: Int = 0) {
        let state = LockedValueBox(State(verifier: ResourceVerifier(seed: seed)))
        self.state = state

        task = _Concurrency.Task {
            do {
                for try await chunk in bytes {
                    state.withLockedValue { $0.verifier.consume(chunk) }
                }

                state.withLockedValue { $0.outcome = .finished }
            } catch {
                state.withLockedValue {
                    $0.outcome = .failed(String(describing: type(of: error)))
                    $0.error = ErrorBox(error)
                }
            }
        }
    }

    /// The position once it has stopped moving for half a second: everything the reader can get
    /// without the producer producing anything new.
    func settledPosition() async throws -> Int {
        var last = -1
        var quietPolls = 0

        for _ in 0..<6_000 {
            let current = position

            if outcome != nil {
                return current
            }

            if current == last {
                quietPolls += 1

                if quietPolls >= 50 {
                    return current
                }
            } else {
                last = current
                quietPolls = 0
            }

            try await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
        }

        return position
    }

    /// Waits for the read to end, one way or the other.
    @discardableResult
    func end(within timeout: Double = 60) async throws -> ReadOutcome {
        try await eventually(timeout: timeout) { self.outcome != nil }
        return try #require(outcome)
    }

    func cancel() {
        task.cancel()
    }
}
