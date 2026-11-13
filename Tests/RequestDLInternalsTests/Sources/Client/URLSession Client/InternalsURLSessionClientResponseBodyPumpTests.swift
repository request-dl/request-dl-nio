//
// See LICENSE for this package's licensing information.
//

// Darwin only, like `Internals.URLSessionClient` itself, and free of NIO for the same reason as
// `InternalsURLSessionClientBackPressureTests`: this suite also runs `--disable-default-traits`,
// where `.urlSession` is the only executor there is.
#if canImport(Darwin)

import Darwin
import Foundation
import SwiftAsyncStream
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

/// What `Internals.URLSessionClient.pumpResponseBody` does with a body that has no boundary to cut
/// at (`.passthrough`, which `DataTask` reads with): it hands bytes over as they arrive, instead of
/// batching them until `maximumPendingBytes` have piled up.
///
/// A body that is slow but steady (a report generated piece by piece, a long poll with keep-alive)
/// has to keep the read timeout (`Internals.IdleDeadline`) and the progress observer fed, and both
/// are only fed by what reaches `Internals.DownloadBuffer`. Each test here has a server that decides
/// exactly when the next piece goes out, so none of them depends on how long the machine takes.
@Suite(
    .serialized,
    .concurrent(watchdogAffectedPlatformConcurrencyLimit),
    .nonFatalWatchdog
)
struct InternalsURLSessionClientResponseBodyPumpTests {

    /// The read timeout every test gives a request, in a fake clock's time.
    private static let budget: Int64 = 10_000_000_000

    // MARK: - Slow but steady

    /// Twelve pieces of 100 bytes, each one well inside the budget of the one before it, add up to
    /// more than the budget in all, and to a tiny fraction of `maximumPendingBytes`. Every piece
    /// has to start the budget over, or the request fails while bytes are still coming in.
    @Test
    func passthrough_aBodyThatTrickles_keepsTheReadTimeoutFromRunningOut() async throws {
        let pieceSize = 100
        let pieceCount = 12

        try await withPacedServer(totalBytes: pieceSize * pieceCount, initialBytes: pieceSize) { server in
            // Given
            let clock = FakeIdleClock()
            let deadline = clock.makeDeadline(nanoseconds: Self.budget)
            deadline.start()
            defer { deadline.finish() }

            let control = Internals.TransferControl(observer: Internals.ExecutionObserver(idle: deadline))
            let (task, step) = try await startDownload(server, transferControl: control)
            let reading = read(step)

            // When: a piece at a time, with almost the whole budget going by after each.
            for piece in 1...pieceCount {
                if piece > 1 {
                    server.send(pieceSize)
                }

                // Each piece reaches the reader as it came, not with the next one: that is when it
                // has fed the deadline.
                try await eventually(timeout: 10) { reading.bytesReceived >= piece * pieceSize }

                await clock.advance(by: Self.budget - 1_000_000_000)
            }

            // Then
            let received = try await completing(within: 10) { await reading.result }

            #expect(!deadline.isExpired)
            #expect(received.isIntact)
            #expect(received.count == pieceSize * pieceCount)

            withExtendedLifetime(task) {}
        }
    }

    /// The counterpart to the test above, so that one passing means something: a body that does stop
    /// coming in for a whole budget still runs the deadline out.
    @Test
    func passthrough_aBodyThatGoesSilent_stillRunsTheReadTimeoutOut() async throws {
        try await withPacedServer(totalBytes: 1_048_576, initialBytes: 100) { server in
            // Given
            let clock = FakeIdleClock()
            let deadline = clock.makeDeadline(nanoseconds: Self.budget)
            deadline.start()
            defer { deadline.finish() }

            let control = Internals.TransferControl(observer: Internals.ExecutionObserver(idle: deadline))
            let (task, step) = try await startDownload(server, transferControl: control)
            let reading = read(step)

            try await eventually(timeout: 10) { reading.bytesReceived >= 100 }

            // When
            await clock.advanceUntilDone(deadline, by: Self.budget)

            // Then
            #expect(deadline.isExpired)

            withExtendedLifetime(task) {}
        }
    }

    // MARK: - Nothing held back

    /// Far less than `maximumPendingBytes` arrives, and then the server goes quiet with the rest of
    /// the body still to come: what did arrive reaches the reader anyway, without waiting for the
    /// rest to fill a batch.
    @Test
    func passthrough_whatHasArrived_reachesTheReaderWithoutWaitingForMoreOfTheBody() async throws {
        let arrived = 5_000

        try await withPacedServer(totalBytes: 1_048_576, initialBytes: arrived) { server in
            // Given
            let (task, step) = try await startDownload(server)
            let reading = read(step)

            // Then
            try await eventually(timeout: 10) { reading.bytesReceived == arrived }
            #expect(server.bytesWritten == arrived)

            server.send(1_048_576 - arrived)

            let received = try await completing(within: 30) { await reading.result }
            #expect(received.isIntact)
            #expect(received.count == 1_048_576)

            withExtendedLifetime(task) {}
        }
    }

    /// The bytes come in however the network cut them, so a body arriving all at once is handed over
    /// in blocks no bigger than `maximumPendingBytes`, whole and in order.
    @Test
    func passthrough_aLargeBody_arrivesIntactInBoundedChunks() async throws {
        let totalBytes = 8 * 1_048_576

        try await withPacedServer(totalBytes: totalBytes, initialBytes: totalBytes) { server in
            // Given
            let (task, step) = try await startDownload(server)
            let reading = read(step)

            // Then
            let received = try await completing(within: 60) { await reading.result }

            #expect(received.isIntact)
            #expect(received.count == totalBytes)
            #expect(received.largestChunk <= Internals.URLSessionClient.maximumPendingBytes)

            // Far fewer than one per delivery of the network: the bytes are batched while they
            // keep coming.
            #expect(received.chunkCount < totalBytes / 8_192)

            withExtendedLifetime(task) {}
        }
    }

    /// A body a `URLProtocol` produced has no socket behind it, and its pieces come in with no time
    /// between them. It arrives whole and in order all the same.
    @Test
    func passthrough_aBodyFromAURLProtocol_arrivesIntact() async throws {
        let totalBytes = 10_000

        // Given
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PiecewiseBodyProtocol.self]
        PiecewiseBodyProtocol.body = PacedServer.slice(from: 0, count: totalBytes)

        let client = try Internals.URLSessionClient(configuration: configuration)

        // When
        let task = try await client.execute(
            request: URLRequest(url: try #require(URL(string: "http://piecewise.test/"))),
            readingMode: .passthrough,
            uploadingBytes: .zero,
            decompression: .disabled,
            cache: nil,
            logger: nil
        )

        var step: Internals.DownloadStep?

        for try await item in task.response {
            if case .download(let download) = item {
                step = download
                break
            }
        }

        let reading = read(try #require(step))
        let received = try await completing(within: 30) { await reading.result }

        // Then
        #expect(received.isIntact)
        #expect(received.count == totalBytes)
    }
}

// MARK: - Helpers

private func startDownload(
    _ server: PacedServer,
    readingMode: Internals.DownloadStep.ReadingMode = .passthrough,
    transferControl: Internals.TransferControl? = nil
) async throws -> (SessionTask, Internals.DownloadStep) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 600

    let client = try Internals.URLSessionClient(configuration: configuration)
    let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/"))

    let task = try await client.execute(
        request: URLRequest(url: url),
        readingMode: readingMode,
        uploadingBytes: .zero,
        decompression: .disabled,
        cache: nil,
        logger: nil,
        transferControl: transferControl
    )

    for try await step in task.response {
        if case .download(let download) = step {
            return (task, download)
        }
    }

    throw AnyError()
}

/// What a reader of `step.bytes` saw.
private struct ReceivedBody: Sendable {
    private(set) var count = 0
    private(set) var chunkCount = 0
    private(set) var largestChunk = 0
    private(set) var isIntact = true

    mutating func consume(_ chunk: Data) {
        if chunk != PacedServer.slice(from: count, count: chunk.count) {
            isIntact = false
        }

        count += chunk.count
        chunkCount += 1
        largestChunk = max(largestChunk, chunk.count)
    }

    mutating func markFailed() {
        isIntact = false
    }
}

/// Reads `step.bytes` to the end on a task of its own, keeping count as it goes.
private final class BodyReading: Sendable {

    private let progress = LockedValueBox(ReceivedBody())
    private let task: _Concurrency.Task<ReceivedBody, Never>

    var bytesReceived: Int {
        progress.withLockedValue { $0.count }
    }

    var result: ReceivedBody {
        get async { await task.value }
    }

    init(_ step: Internals.DownloadStep) {
        let progress = progress

        task = _Concurrency.Task {
            do {
                for try await chunk in step.bytes {
                    progress.withLockedValue { $0.consume(chunk) }
                }
            } catch {
                progress.withLockedValue { $0.markFailed() }
            }

            return progress.withLockedValue { $0 }
        }
    }

    deinit {
        task.cancel()
    }
}

private func read(_ step: Internals.DownloadStep) -> BodyReading {
    BodyReading(step)
}

/// Answers every request with `body`, in pieces of 700 bytes.
private final class PiecewiseBodyProtocol: URLProtocol, @unchecked Sendable {

    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.body
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/octet-stream", "Content-Length": "\(body.count)"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        for start in stride(from: 0, to: body.count, by: 700) {
            client?.urlProtocol(self, didLoad: body[start..<min(start + 700, body.count)])
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A server that sends the bytes of the response body when told to, and not before: the pace of
/// the body is the test's, down to the byte.
///
/// Plain BSD sockets (see `InternalsURLSessionClientBackPressureTests`'s `RawStreamingServer`, which
/// this is a smaller sibling of: that one decides by itself when to pause, this one has no clock).
/// The body is the pattern `byte(at:)`, announced with a `Content-Length` of `totalBytes`.
private final class PacedServer: @unchecked Sendable {

    let port: Int
    let totalBytes: Int

    var bytesWritten: Int {
        lock.withLock { _bytesWritten }
    }

    var isFinished: Bool {
        lock.withLock { _isFinished }
    }

    private let listener: Int32
    private let lock = Lock()
    private let wakeUp = DispatchSemaphore(value: 0)

    private var _bytesWritten = 0
    private var _allowed = 0
    private var _isStopped = false
    private var _isFinished = false
    private var _connection: Int32 = -1

    private static let blockSize = 65_536

    /// `blockSize` bytes of the pattern from every possible phase, so any slice of the body up to
    /// that size is a slice of this.
    private static let pattern = Data((0..<(blockSize + 251)).map { UInt8(truncatingIfNeeded: $0 % 251) })

    /// The bytes of the body from `position`, at most `blockSize` of them.
    static func slice(from position: Int, count: Int) -> Data {
        let phase = position % 251
        return Data(pattern[phase..<phase + count])
    }

    /// - Parameter initialBytes: How much of the body goes out right after the head, without being
    ///   asked for. `URLSession.bytes(for:)` only returns once the first of the body is in, so a
    ///   test that wants a response to start with has to let some of it out.
    init(totalBytes: Int, initialBytes: Int) throws {
        self.totalBytes = totalBytes
        self._allowed = initialBytes

        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let isListening = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, length) == 0 && listen(listener, 8) == 0 && getsockname(listener, $0, &length) == 0
            }
        }

        guard isListening else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(listener)
            throw error
        }

        self.listener = listener
        self.port = Int(UInt16(bigEndian: address.sin_port))

        Thread.detachNewThread { [self] in
            run()
        }
    }

    /// Lets `count` more bytes of the body go out, in one write.
    func send(_ count: Int) {
        lock.withLock { _allowed += count }
        wakeUp.signal()
    }

    fileprivate func stop() {
        let connection = lock.withLock { () -> Int32 in
            _isStopped = true
            return _connection
        }

        if connection >= 0 {
            shutdown(connection, SHUT_RDWR)
        }

        wakeUp.signal()
    }

    private func run() {
        defer {
            close(listener)
            lock.withLock { _isFinished = true }
        }

        while !lock.withLock({ _isStopped }) {
            var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)

            guard poll(&descriptor, 1, 50) > 0 else {
                continue
            }

            let connection = accept(listener, nil, nil)

            guard connection >= 0 else {
                continue
            }

            serve(connection)
        }
    }

    private func serve(_ connection: Int32) {
        lock.withLock { _connection = connection }

        defer {
            lock.withLock { _connection = -1 }
            close(connection)
        }

        var enabled: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(connection, IPPROTO_TCP, TCP_NODELAY, &enabled, socklen_t(MemoryLayout<Int32>.size))

        // The request is one `GET`, with no body: its head ends at the first blank line.
        var received = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 4_096)

        while !received.suffix(4).elementsEqual(Array("\r\n\r\n".utf8)) {
            let count = recv(connection, &chunk, chunk.count, 0)

            guard count > 0 else {
                return
            }

            received += chunk[0..<count]
        }

        // `Content-Type` matters: without one, CFNetwork holds the response back to sniff a MIME
        // type from the first 512 body bytes.
        let head =
            "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
            + "Content-Length: \(totalBytes)\r\n\r\n"

        guard write(connection, Array(head.utf8)) else {
            return
        }

        var position = 0

        while position < totalBytes {
            let (count, isStopped) = lock.withLock { () -> (Int, Bool) in
                (min(_allowed, totalBytes) - position, _isStopped)
            }

            guard !isStopped else {
                return
            }

            guard count > 0 else {
                wakeUp.wait()
                continue
            }

            // In writes of `blockSize` at most; the first of them is the whole of a small piece.
            var written = 0

            while written < count {
                let size = min(Self.blockSize, count - written)
                let bytes = Array(Self.slice(from: position + written, count: size))

                guard write(connection, bytes) else {
                    return
                }

                written += size
                lock.withLock { _bytesWritten += size }
            }

            position += count
        }

        // The whole body is out: wait for the client to close its end, or for `stop()`.
        var byte: UInt8 = 0
        while recv(connection, &byte, 1, 0) > 0 {}
    }

    private func write(_ connection: Int32, _ bytes: [UInt8]) -> Bool {
        var offset = 0

        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes {
                Darwin.send(connection, $0.baseAddress! + offset, bytes.count - offset, 0)
            }

            guard sent > 0 else {
                return false
            }

            offset += sent
        }

        return true
    }
}

private func withPacedServer<Result>(
    totalBytes: Int,
    initialBytes: Int,
    perform body: (PacedServer) async throws -> Result
) async throws -> Result {
    let server = try PacedServer(totalBytes: totalBytes, initialBytes: initialBytes)

    do {
        let result = try await body(server)
        server.stop()
        try await eventually { server.isFinished }
        return result
    } catch {
        server.stop()
        try? await eventually { server.isFinished }
        throw error
    }
}

#endif
