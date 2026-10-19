//
// See LICENSE for this package's licensing information.
//

import Dispatch
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// `lines()` and `events(maximumLineLength:)` against a real server on every executor, which the
/// tests of the sequences themselves (a hand-made stream of chunks) cannot show: that a slow
/// reader holds the connection back instead of the body piling up, and that a response that
/// never ends is cut off once its line is over the limit.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct AsyncBytesServerTests {

    private typealias Executor = TransferTestExecutor

    // MARK: - A slow reader

    /// The body is lines (the pattern of ``TransferServer`` has a line break every 251 bytes), far
    /// more than the connection and the response window can hold. A reader that stops after its
    /// first line stops draining the socket, which the server sees as a stalled connection: the
    /// body was not read into memory to keep up with it.
    @Test(arguments: Executor.allCases)
    private func lines_whenTheReaderPauses_theServerIsHeldBack(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 48 * 1_048_576)) { server in
            // Given
            server.stallTimeout = 1

            let download = DownloadTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
                executor.session
            }

            let bytes = try await download.result().payload
            var lines = bytes.lines().makeAsyncIterator()

            // When: one line is read, and then nothing is, for longer than the server's patience.
            _ = try await lines.next()

            // Then
            try await eventually(timeout: 120) { server.stalledConnections == 1 }
        }
    }

    // MARK: - A response that never ends

    @Test(arguments: Executor.allCases)
    private func events_whenALineNeverEnds_failsAndTheTransferIsCancelled(_ executor: Executor) async throws {
        let server = try EndlessLineServer()
        defer { server.stop() }

        // Given
        let download = DownloadTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/events")
            executor.session
        }

        let bytes = try await download.result().payload

        // When: the line passes the limit.
        await #expect(throws: AsyncBytesItemTooLargeError(maximumLength: 16_384)) {
            for try await _ in bytes.events(maximumLineLength: 16_384) {}
        }

        // Then: the server's writes start failing, since the client cut the connection, long
        // before the body, which has no end, could have been read.
        try await eventually(timeout: 120) { server.writeFailed }
    }
}

// MARK: - A server that never ends a line

/// Answers any request with `text/event-stream` and then writes `data: xxxx...` for ever, without
/// a line break, until a write fails because the client closed the connection.
private final class EndlessLineServer: @unchecked Sendable {

    private let listener: Int32
    private let lock = NSLockBox()
    private var _writeFailed = false

    let port: Int

    var writeFailed: Bool {
        lock.withLock { _writeFailed }
    }

    init() throws {
        let descriptor = socket(AF_INET, Int32(SOCK_STREAM), 0)

        guard descriptor >= 0 else {
            throw POSIXError()
        }

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bound == 0, listen(descriptor, 8) == 0 else {
            close(descriptor)
            throw POSIXError()
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        _ = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }

        listener = descriptor
        port = Int(UInt16(bigEndian: assigned.sin_port))

        DispatchQueue.global().async { [self] in
            while true {
                let connection = accept(descriptor, nil, nil)

                guard connection >= 0 else {
                    return
                }

                serve(connection)
            }
        }
    }

    func stop() {
        shutdown(listener, Int32(SHUT_RDWR))
        close(listener)
    }

    private func serve(_ connection: Int32) {
        // A write to a connection the client has closed must fail with an error, not raise
        // `SIGPIPE`, which ends the process.
        #if canImport(Darwin)
        var noSignal: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        #endif

        // Not read to the end: the request is a few hundred bytes, and one read takes it.
        var request = [UInt8](repeating: 0, count: 4_096)
        _ = recv(connection, &request, request.count, 0)

        let head = Array("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n".utf8)

        guard writeAll(head, to: connection) else {
            close(connection)
            return
        }

        let line = [UInt8](repeating: UInt8(ascii: "x"), count: 4_096)

        while writeAll(line, to: connection) {}

        lock.withLock { _writeFailed = true }
        close(connection)
    }

    #if canImport(Darwin)
    private static let sendFlags: Int32 = 0
    #else
    private static let sendFlags = Int32(MSG_NOSIGNAL)
    #endif

    private func writeAll(_ bytes: [UInt8], to connection: Int32) -> Bool {
        var sent = 0

        while sent < bytes.count {
            let count = bytes.withUnsafeBytes {
                send(connection, $0.baseAddress! + sent, bytes.count - sent, Self.sendFlags)
            }

            guard count > 0 else {
                return false
            }

            sent += count
        }

        return true
    }
}

private struct POSIXError: Error {}

/// A lock for a few flags, without pulling a library in.
private final class NSLockBox: @unchecked Sendable {

    private var mutex = pthread_mutex_t()

    init() {
        pthread_mutex_init(&mutex, nil)
    }

    func withLock<Result>(_ body: () -> Result) -> Result {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }

        return body()
    }
}
