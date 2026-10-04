//
// See LICENSE for this package's licensing information.
//

import Dispatch
import SwiftAsyncStream

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#endif

/// A bare HTTP/1.1 server on plain BSD sockets, for suspend/resume and download-resumption tests
/// that have to observe the *wire*: how many body bytes the kernel actually accepted (or
/// delivered), which requests arrived with which headers, and what happens when a connection is
/// dropped at an exact byte.
///
/// Free of NIO on purpose, and portable between Darwin and Glibc, so the same server drives the
/// `.nio` executor on every platform and the `.urlSession` one under `--disable-default-traits`.
///
/// ## Downloads (`GET`)
///
/// Serves one resource of ``Resource/length`` bytes, a position-dependent pattern (see
/// ``byte(at:seed:)``) whose `seed` stands for its version: changing ``resource`` mid-test is
/// changing the resource on the server, and bytes of two versions spliced together can't pass for
/// either. Honours `Range: bytes=N-` and `If-Range` like a compliant origin (both can be turned off
/// to play a non-compliant one), with a strong `ETag`, a weak one, a `Last-Modified`, or no
/// validator at all.
///
/// ## Uploads (`PUT`/`POST`)
///
/// Reads the body (`Content-Length` or chunked), checks every byte against ``uploadByte(at:)``,
/// and counts what arrived as it arrives.
///
/// ## Scripted failures
///
/// - ``dropPlan``/``uploadDropPlan``: per request, the body byte after which the connection is cut.
/// - ``stallTimeout``: a connection that can't make progress (the client stopped reading, or
///   stopped sending) for that long is closed, the way a server's own idle timeout
///   (`send_timeout`, `client_body_timeout`) or a middlebox's would.
/// - ``closeConnections()``: cut every open connection now.
///
/// Small, fixed socket buffers on the server's side, so a stall shows up early and unambiguously.
package final class TransferServer: @unchecked Sendable {

    // MARK: - Inner types

    package enum Validator: Sendable, Hashable {
        case entityTag(String)
        case weakEntityTag(String)
        /// `Last-Modified`, with a `Date` far enough after it to make it strong.
        case lastModified(String, date: String)
        case none
    }

    package struct Resource: Sendable {
        package var length: Int
        package var seed: Int
        package var validator: Validator
        package var supportsRanges: Bool
        package var honorsIfRange: Bool
        package var isChunked: Bool
        package var contentEncoding: String?

        package init(
            length: Int,
            seed: Int = 0,
            validator: Validator = .entityTag("\"v1\""),
            supportsRanges: Bool = true,
            honorsIfRange: Bool = true,
            isChunked: Bool = false,
            contentEncoding: String? = nil
        ) {
            self.length = length
            self.seed = seed
            self.validator = validator
            self.supportsRanges = supportsRanges
            self.honorsIfRange = honorsIfRange
            self.isChunked = isChunked
            self.contentEncoding = contentEncoding
        }
    }

    package struct ReceivedRequest: Sendable {
        package let method: String
        package let path: String
        package let headers: [(name: String, value: String)]
        package let bodyLength: Int
        package let isBodyIntact: Bool
        package let isBodyComplete: Bool
        package let status: Int

        package func header(_ name: String) -> String? {
            headers.first { $0.name.lowercased() == name.lowercased() }?.value
        }
    }

    /// Which resumable upload protocol the server speaks, when it speaks one.
    package enum ResumableProtocol: Sendable, Hashable {
        /// `draft-ietf-httpbis-resumable-upload`: an upload is created by a request carrying
        /// `Upload-Complete: ?0`, its bytes go in `PATCH` requests, and the response to the
        /// `PATCH` that completes it is the response of the application.
        case ietf

        /// tus 1.0 with the creation extension.
        case tus
    }

    /// What the server holds of one upload it created.
    package struct HeldUpload: Sendable {
        package var data: [UInt8] = []
        package var length: Int?
        package var isComplete = false
    }

    // MARK: - Internal properties

    package let port: Int

    package var resource: Resource {
        get { lock.withLock { _resource } }
        set { lock.withLock { _resource = newValue } }
    }

    /// Consumed one entry per `GET`: the body bytes after which that response's connection is cut
    /// (`nil`: sent whole).
    package var dropPlan: [Int?] {
        get { lock.withLock { _dropPlan } }
        set { lock.withLock { _dropPlan = newValue } }
    }

    /// Consumed one entry per upload: the body bytes after which that request's connection is cut.
    package var uploadDropPlan: [Int?] {
        get { lock.withLock { _uploadDropPlan } }
        set { lock.withLock { _uploadDropPlan = newValue } }
    }

    /// Seconds a connection may go without progress before the server gives up on it.
    package var stallTimeout: Double? {
        get { lock.withLock { _stallTimeout } }
        set { lock.withLock { _stallTimeout = newValue } }
    }

    /// Microseconds to wait after every read of an upload body: a server slower than loopback,
    /// so an upload is still mostly unsent -- rather than sitting whole in socket buffers --
    /// when a test suspends it.
    package var uploadReadDelay: UInt32 {
        get { lock.withLock { _uploadReadDelay } }
        set { lock.withLock { _uploadReadDelay = newValue } }
    }

    /// Called on the serving thread after every read of an upload body, with the body bytes that
    /// request has received so far. Lets a test act at an exact point of the upload, independently
    /// of how promptly its own task gets scheduled.
    package var onUploadProgress: (@Sendable (Int) -> Void)? {
        get { lock.withLock { _onUploadProgress } }
        set { lock.withLock { _onUploadProgress = newValue } }
    }

    /// Answer the first upload with a `307` to `/final` (after reading its body), so the client
    /// has to send the body again.
    package var redirectsFirstUpload: Bool {
        get { lock.withLock { _redirectsFirstUpload } }
        set { lock.withLock { _redirectsFirstUpload = newValue } }
    }

    /// The resumable upload protocol the server speaks. `nil` (the default) leaves `PUT`/`POST`
    /// as plain uploads and everything else as downloads. When set, a request that creates an
    /// upload, and every request to `/uploads/<id>`, is handled as that protocol says; the rest is
    /// served as before.
    package var resumableProtocol: ResumableProtocol? {
        get { lock.withLock { _resumableProtocol } }
        set { lock.withLock { _resumableProtocol = newValue } }
    }

    /// The uploads the server created, by the id in their URL.
    package var heldUploads: [Int: HeldUpload] {
        lock.withLock { _heldUploads }
    }

    /// Bytes the server forgets of an upload right before it looks at the next `PATCH`, the way a
    /// server that lost part of what it was sent would: the `PATCH` then starts from an offset
    /// that is not the one the server holds.
    package var forgetsBytesBeforeNextPatch: Int {
        get { lock.withLock { _forgetsBytesBeforeNextPatch } }
        set { lock.withLock { _forgetsBytesBeforeNextPatch = newValue } }
    }

    /// Drop every upload right before the next request about one, as an expired upload is.
    package var expiresUploadsBeforeNextRequest: Bool {
        get { lock.withLock { _expiresUploadsBeforeNextRequest } }
        set { lock.withLock { _expiresUploadsBeforeNextRequest = newValue } }
    }

    /// The status the next request that creates an upload is answered with, in place of success.
    package var creationStatus: Int? {
        get { lock.withLock { _creationStatus } }
        set { lock.withLock { _creationStatus = newValue } }
    }

    /// Answer the next request that creates an upload without a `Location`.
    package var omitsLocationOnCreation: Bool {
        get { lock.withLock { _omitsLocationOnCreation } }
        set { lock.withLock { _omitsLocationOnCreation = newValue } }
    }

    /// Cut the connection instead of answering the `PATCH` that completes an upload, once: the
    /// server has the whole body and the client never hears it.
    package var dropsFinalResponse: Bool {
        get { lock.withLock { _dropsFinalResponse } }
        set { lock.withLock { _dropsFinalResponse = newValue } }
    }

    /// Every request that got as far as a complete head, in arrival order, recorded once it's
    /// done (answered, dropped, or failed).
    package var requests: [ReceivedRequest] {
        lock.withLock { _requests }
    }

    /// Download body bytes the kernel accepted, over every connection.
    package var bodyBytesWritten: Int {
        lock.withLock { _bodyBytesWritten }
    }

    /// Upload body bytes received, over every connection, as they arrive.
    package var uploadBytesReceived: Int {
        lock.withLock { _uploadBytesReceived }
    }

    package var acceptedConnections: Int {
        lock.withLock { _acceptedConnections }
    }

    package var openConnections: Int {
        lock.withLock { _connections.count }
    }

    /// Connections the server closed because of ``stallTimeout``.
    package var stalledConnections: Int {
        lock.withLock { _stalledConnections }
    }

    // MARK: - Private properties

    private let listener: Int32
    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _resource: Resource
    private var _dropPlan: [Int?] = []
    private var _uploadDropPlan: [Int?] = []
    private var _stallTimeout: Double?
    private var _uploadReadDelay: UInt32 = .zero
    private var _onUploadProgress: (@Sendable (Int) -> Void)?
    private var _redirectsFirstUpload = false
    private var _resumableProtocol: ResumableProtocol?
    private var _heldUploads: [Int: HeldUpload] = [:]
    private var _nextUploadID = 1
    private var _forgetsBytesBeforeNextPatch = 0
    private var _expiresUploadsBeforeNextRequest = false
    private var _creationStatus: Int?
    private var _omitsLocationOnCreation = false
    private var _dropsFinalResponse = false
    private var _requests: [ReceivedRequest] = []
    private var _bodyBytesWritten = 0
    private var _uploadBytesReceived = 0
    private var _acceptedConnections = 0
    private var _stalledConnections = 0
    private var _uploadCount = 0
    private var _connections: Set<Int32> = []
    private var _activeThreads = 0
    private var _isStopped = false

    // MARK: - Inits

    package init(resource: Resource) throws {
        self._resource = resource

        // An enum on Glibc, a plain `Int32` everywhere else (Darwin, Musl, Bionic).
        #if canImport(Glibc)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif

        #if !canImport(Darwin)
        // Writes to a socket the client already closed must fail, not kill the test process.
        signal(SIGPIPE, SIG_IGN)
        #endif

        let listener = socket(AF_INET, socketType, 0)

        guard listener >= 0 else {
            throw TransferServerError(code: errno)
        }

        var reuse: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // On the listener, not just on each accepted socket: the receive window is advertised
        // during the handshake, before `accept(2)` hands the connection over, so only a buffer
        // inherited from the listener actually keeps the client from sending far ahead.
        var receiveBuffer: Int32 = 32_768
        setsockopt(listener, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let isListening = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, length) == 0 && listen(listener, 16) == 0 && getsockname(listener, $0, &length) == 0
            }
        }

        guard isListening else {
            let error = TransferServerError(code: errno)
            close(listener)
            throw error
        }

        self.listener = listener
        self.port = Int(UInt16(bigEndian: address.sin_port))

        enterThread()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            acceptLoop()
            leaveThread()
        }
    }

    // MARK: - Internal static methods

    /// Byte `position` of the resource in its version `seed`.
    package static func byte(at position: Int, seed: Int) -> UInt8 {
        UInt8(truncatingIfNeeded: (position &+ seed &* 7) % 251)
    }

    /// `count` bytes of the resource in its version `seed`, from `position`. Sliced out of one
    /// precomputed stretch of the pattern for pieces up to ``maximumPiece``, so serving, and
    /// checking, a body of tens of MiB stays cheap in a Debug build.
    package static func body(from position: Int, count: Int, seed: Int) -> ArraySlice<UInt8> {
        guard count <= maximumPiece else {
            return ArraySlice((position..<position + count).map { byte(at: $0, seed: seed) })
        }

        let phase = (position &+ seed &* 7) % 251
        return downloadPattern[phase..<phase + count]
    }

    /// Byte `position` of every upload body these tests send. Shifts every 251 bytes, over a
    /// period of 64,256, so a skipped or repeated stretch of any plausible length is caught.
    package static func uploadByte(at position: Int) -> UInt8 {
        UInt8(truncatingIfNeeded: (position % 251) ^ ((position / 251) & 0xFF))
    }

    /// `count` upload bytes from `position`, sliced out of a precomputed stretch for pieces up to
    /// ``maximumPiece``.
    package static func uploadBody(from position: Int, count: Int) -> ArraySlice<UInt8> {
        guard count <= maximumPiece else {
            return ArraySlice((position..<position + count).map(uploadByte(at:)))
        }

        let phase = position % uploadPeriod
        return uploadPattern[phase..<phase + count]
    }

    /// The largest piece ``body(from:count:seed:)``/``uploadBody(from:count:)`` slice without
    /// computing anything.
    package static let maximumPiece = 65_536

    private static let uploadPeriod = 251 * 256

    private static let downloadPattern: [UInt8] = (0..<(maximumPiece + 251)).map {
        UInt8(truncatingIfNeeded: $0 % 251)
    }

    private static let uploadPattern: [UInt8] = (0..<(maximumPiece + uploadPeriod)).map(uploadByte(at:))

    // MARK: - Internal methods

    /// Cuts every open connection from the server's side, the way a server or middlebox giving up
    /// would.
    package func closeConnections() {
        // Under the lock, the same one a serving thread closes its descriptor under, so a
        // descriptor already closed (and possibly reused by then) is never shut down by mistake.
        lock.withLock {
            for connection in _connections {
                shutdown(connection, CInt(SHUT_RDWR))
            }
        }
    }

    /// Waits for `value` to stop moving for half a second, or to reach `target`, and returns it.
    package func settled(_ value: @Sendable () -> Int, target: Int = .max) async throws -> Int {
        var last = -1
        var quietPolls = 0

        for _ in 0..<6_000 {
            let current = value()

            if current >= target {
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

        return value()
    }

    /// Stops accepting, cuts every connection, and waits for every serving thread to finish.
    package func stop() async {
        lock.withLock { _isStopped = true }
        closeConnections()

        // Polled rather than blocking on the threads, which would block a cooperative thread.
        while lock.withLock({ _activeThreads }) > 0 {
            closeConnections()
            try? await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        }

        close(listener)
    }

    // MARK: - Serving

    private func acceptLoop() {
        while !lock.withLock({ _isStopped }) {
            var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)

            guard poll(&descriptor, 1, 20) > 0 else {
                continue
            }

            let connection = accept(listener, nil, nil)

            guard connection >= 0 else {
                continue
            }

            let isStopped = lock.withLock { () -> Bool in
                _acceptedConnections += 1
                _connections.insert(connection)
                return _isStopped
            }

            guard !isStopped else {
                release(connection)
                continue
            }

            enterThread()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                serve(connection)
                release(connection)
                leaveThread()
            }
        }
    }

    private func enterThread() {
        lock.withLock { _activeThreads += 1 }
    }

    private func leaveThread() {
        lock.withLock { _activeThreads -= 1 }
    }

    private func release(_ connection: Int32) {
        lock.withLock {
            _ = _connections.remove(connection)
            close(connection)
        }
    }

    private func serve(_ connection: Int32) {
        #if canImport(Darwin)
        var enabled: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var bufferSize: Int32 = 32_768
        setsockopt(connection, SOL_SOCKET, SO_SNDBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(connection, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))

        var io = TransferServerIO(connection: connection, server: self)

        // Keep-alive: one request after another, until the client closes or a script cuts in.
        while let head = io.readHead() {
            let keepGoing: Bool

            if let isKept = serveResumableUpload(head, io: &io) {
                keepGoing = isKept
                guard keepGoing else {
                    return
                }

                continue
            }

            switch head.method {
            case "PUT", "POST":
                keepGoing = serveUpload(head, io: &io)
            default:
                keepGoing = serveDownload(head, io: &io)
            }

            guard keepGoing else {
                return
            }
        }
    }

    private func serveDownload(_ head: TransferServerIO.Head, io: inout TransferServerIO) -> Bool {
        let (resource, dropAfter) = lock.withLock { () -> (Resource, Int?) in
            let dropAfter = _dropPlan.isEmpty ? nil : _dropPlan.removeFirst()
            return (_resource, dropAfter)
        }

        var status = 200
        var start = 0
        var headers: [(String, String)] = [("Content-Type", "application/octet-stream")]

        switch resource.validator {
        case .entityTag(let value), .weakEntityTag(let value):
            headers.append(("ETag", value))
        case .lastModified(let lastModified, let date):
            headers.append(("Last-Modified", lastModified))
            headers.append(("Date", date))
        case .none:
            break
        }

        if resource.supportsRanges {
            headers.append(("Accept-Ranges", "bytes"))
        }

        if let contentEncoding = resource.contentEncoding {
            headers.append(("Content-Encoding", contentEncoding))
        }

        if resource.supportsRanges, let first = Self.rangeStart(head.header("Range")) {
            let validatorMatches: Bool

            if let ifRange = head.header("If-Range"), resource.honorsIfRange {
                switch resource.validator {
                case .entityTag(let value):
                    validatorMatches = ifRange == value
                case .lastModified(let value, _):
                    validatorMatches = ifRange == value
                case .weakEntityTag, .none:
                    // RFC 9110 §13.1.5: a weak or absent validator never matches.
                    validatorMatches = false
                }
            } else {
                validatorMatches = true
            }

            if validatorMatches {
                if first >= resource.length {
                    let response = Self.head(
                        status: 416,
                        headers: headers + [("Content-Range", "bytes */\(resource.length)"), ("Content-Length", "0")]
                    )

                    let isSent = io.send(response, counted: false)
                    record(head, bodyLength: 0, isIntact: true, isComplete: true, status: 416)
                    return isSent
                }

                status = 206
                start = first
                headers.append(("Content-Range", "bytes \(first)-\(resource.length - 1)/\(resource.length)"))
            }
        }

        let count = resource.length - start

        if resource.isChunked {
            headers.append(("Transfer-Encoding", "chunked"))
        } else {
            headers.append(("Content-Length", String(count)))
        }

        guard io.send(Self.head(status: status, headers: headers), counted: false) else {
            record(head, bodyLength: 0, isIntact: true, isComplete: false, status: status)
            return false
        }

        let limit = dropAfter.map { min($0, count) } ?? count
        var sent = 0

        while sent < limit {
            // A chunk is framed for its full size even when a scripted drop cuts it short, so a
            // drop lands mid-chunk -- where a client can tell the body is truncated -- unless it
            // falls exactly on a chunk boundary.
            let piece = min(16_384, count - sent)
            let taken = min(piece, limit - sent)
            let bytes = Array(Self.body(from: start + sent, count: taken, seed: resource.seed))

            let isSent: Bool

            if resource.isChunked {
                isSent =
                    io.send(Array("\(String(piece, radix: 16))\r\n".utf8), counted: false)
                    && io.send(bytes, counted: true)
                    && (taken < piece || io.send(Array("\r\n".utf8), counted: false))
            } else {
                isSent = io.send(bytes, counted: true)
            }

            guard isSent else {
                record(head, bodyLength: sent, isIntact: true, isComplete: false, status: status)
                return false
            }

            sent += taken
        }

        // Scripted drop: mid-body, or -- for a chunked body -- right after the last byte, before
        // the terminating chunk that would have told the client the body was complete.
        guard sent == count, dropAfter.map({ $0 > count || !resource.isChunked }) ?? true else {
            record(head, bodyLength: sent, isIntact: true, isComplete: false, status: status)
            return false
        }

        if resource.isChunked, !io.send(Array("0\r\n\r\n".utf8), counted: false) {
            record(head, bodyLength: sent, isIntact: true, isComplete: false, status: status)
            return false
        }

        record(head, bodyLength: sent, isIntact: true, isComplete: true, status: status)
        return true
    }

    private func serveUpload(_ head: TransferServerIO.Head, io: inout TransferServerIO) -> Bool {
        let (dropAfter, isRedirected) = lock.withLock { () -> (Int?, Bool) in
            _uploadCount += 1
            let dropAfter = _uploadDropPlan.isEmpty ? nil : _uploadDropPlan.removeFirst()
            return (dropAfter, _redirectsFirstUpload && _uploadCount == 1)
        }

        let outcome = io.readBody(head, dropAfter: dropAfter)

        guard outcome.isComplete else {
            record(head, bodyLength: outcome.length, isIntact: outcome.isIntact, isComplete: false, status: 0)
            return false
        }

        if isRedirected {
            let response = Self.head(
                status: 307,
                headers: [("Location", "/final"), ("Content-Length", "0")]
            )

            let isSent = io.send(response, counted: false)
            record(head, bodyLength: outcome.length, isIntact: outcome.isIntact, isComplete: true, status: 307)
            return isSent
        }

        let body = Array("ok".utf8)
        let response = Self.head(
            status: 200,
            headers: [("Content-Type", "text/plain"), ("Content-Length", String(body.count))]
        )

        let isSent = io.send(response + body, counted: false)
        record(head, bodyLength: outcome.length, isIntact: outcome.isIntact, isComplete: true, status: 200)
        return isSent
    }

    // MARK: - Resumable uploads

    /// `nil` when `head` is not about a resumable upload at all.
    private func serveResumableUpload(_ head: TransferServerIO.Head, io: inout TransferServerIO) -> Bool? {
        guard let dialect = lock.withLock({ _resumableProtocol }) else {
            return nil
        }

        if head.path.hasPrefix("/uploads/") {
            return serveHeldUpload(head, dialect: dialect, io: &io)
        }

        let isCreation: Bool

        switch dialect {
        case .ietf:
            isCreation = head.header("Upload-Complete") == "?0"
        case .tus:
            isCreation = head.method == "POST" && head.header("Tus-Resumable") != nil
        }

        guard isCreation else {
            return nil
        }

        let outcome = io.readBody(head, dropAfter: nil, sink: { _ in })

        guard outcome.isComplete else {
            record(head, bodyLength: outcome.length, isIntact: true, isComplete: false, status: 0)
            return false
        }

        let (id, status, omitsLocation) = lock.withLock { () -> (Int, Int, Bool) in
            let id = _nextUploadID
            _nextUploadID += 1

            let status = _creationStatus ?? 201
            let omitsLocation = _omitsLocationOnCreation
            _creationStatus = nil
            _omitsLocationOnCreation = false

            if (200..<300).contains(status) {
                _heldUploads[id] = HeldUpload(length: head.header("Upload-Length").flatMap { Int($0) })
            }

            return (id, status, omitsLocation)
        }

        var headers: [(String, String)] = [("Content-Length", "0")]

        if (200..<300).contains(status), !omitsLocation {
            headers.append(("Location", "/uploads/\(id)"))
        }

        if dialect == .tus {
            headers.append(("Tus-Resumable", "1.0.0"))
        }

        let isSent = io.send(Self.head(status: status, headers: headers), counted: false)
        record(head, bodyLength: 0, isIntact: true, isComplete: true, status: status)
        return isSent
    }

    private func serveHeldUpload(
        _ head: TransferServerIO.Head,
        dialect: ResumableProtocol,
        io: inout TransferServerIO
    ) -> Bool {
        let id = head.path.split(separator: "/").last.flatMap { Int($0) }

        lock.withLock {
            if _expiresUploadsBeforeNextRequest {
                _heldUploads.removeAll()
                _expiresUploadsBeforeNextRequest = false
            }
        }

        // Read and thrown away whatever body a request has, so that answering it never races the
        // client still writing.
        func discardBody() -> Bool {
            io.readBody(head, dropAfter: nil, sink: { _ in }).isComplete
        }

        func respond(_ status: Int, _ headers: [(String, String)]) -> Bool {
            var headers = headers + [("Content-Length", "0")]

            if dialect == .tus {
                headers.append(("Tus-Resumable", "1.0.0"))
            }

            let isSent = io.send(Self.head(status: status, headers: headers), counted: false)
            record(head, bodyLength: 0, isIntact: true, isComplete: true, status: status)
            return isSent
        }

        guard let id, let held = lock.withLock({ _heldUploads[id] }) else {
            return discardBody() && respond(404, [])
        }

        switch head.method {
        case "HEAD":
            var headers: [(String, String)] = [
                ("Upload-Offset", String(held.data.count)), ("Cache-Control", "no-store"),
            ]

            if let length = held.length {
                headers.append(("Upload-Length", String(length)))
            }

            if dialect == .ietf {
                headers.append(("Upload-Complete", held.isComplete ? "?1" : "?0"))
            }

            // A `HEAD` answer states no length of its own.
            let isSent = io.send(
                Self.head(status: 204, headers: headers + (dialect == .tus ? [("Tus-Resumable", "1.0.0")] : [])),
                counted: false
            )

            record(head, bodyLength: 0, isIntact: true, isComplete: true, status: 204)
            return isSent

        case "DELETE":
            lock.withLock { _heldUploads[id] = nil }
            return respond(204, [])

        case "PATCH":
            return servePatch(head, id: id, dialect: dialect, io: &io)

        default:
            return discardBody() && respond(405, [])
        }
    }

    private func servePatch(
        _ head: TransferServerIO.Head,
        id: Int,
        dialect: ResumableProtocol,
        io: inout TransferServerIO
    ) -> Bool {
        let (dropAfter, offsetHeld) = lock.withLock { () -> (Int?, Int) in
            if _forgetsBytesBeforeNextPatch > 0, var held = _heldUploads[id], !held.data.isEmpty {
                held.data.removeLast(min(_forgetsBytesBeforeNextPatch, held.data.count))
                _heldUploads[id] = held
                _forgetsBytesBeforeNextPatch = 0
            }

            let dropAfter = _uploadDropPlan.isEmpty ? nil : _uploadDropPlan.removeFirst()
            return (dropAfter, _heldUploads[id]?.data.count ?? 0)
        }

        let offsetSent = head.header("Upload-Offset").flatMap { Int($0) }

        guard offsetSent == offsetHeld else {
            let isRead = io.readBody(head, dropAfter: nil, sink: { _ in }).isComplete

            var headers: [(String, String)] = [("Content-Length", "0")]

            if dialect == .ietf {
                headers.append(("Upload-Offset", String(offsetHeld)))
            } else {
                headers.append(("Tus-Resumable", "1.0.0"))
            }

            let isSent = isRead && io.send(Self.head(status: 409, headers: headers), counted: false)
            record(head, bodyLength: 0, isIntact: true, isComplete: isRead, status: 409)
            return isSent
        }

        // What arrives is kept as it arrives, so an upload cut short holds the part that made it:
        // that is what the client is then told.
        let outcome = io.readBody(
            head,
            dropAfter: dropAfter,
            sink: { [self] bytes in
                lock.withLock { _heldUploads[id]?.data.append(contentsOf: bytes) }
            }
        )

        guard outcome.isComplete else {
            record(head, bodyLength: outcome.length, isIntact: true, isComplete: false, status: 0)
            return false
        }

        let (held, dropsResponse) = lock.withLock { () -> (HeldUpload, Bool) in
            var held = _heldUploads[id] ?? HeldUpload()

            switch dialect {
            case .ietf:
                held.isComplete = head.header("Upload-Complete") == "?1"
            case .tus:
                held.isComplete = held.length.map { held.data.count >= $0 } ?? false
            }

            _heldUploads[id] = held

            let dropsResponse = held.isComplete && _dropsFinalResponse
            if dropsResponse {
                _dropsFinalResponse = false
            }

            return (held, dropsResponse)
        }

        guard !dropsResponse else {
            record(head, bodyLength: outcome.length, isIntact: true, isComplete: true, status: 0)
            return false
        }

        let isSent: Bool
        let status: Int

        switch dialect {
        case .ietf where held.isComplete:
            let body = Array("done".utf8)
            status = 200
            isSent = io.send(
                Self.head(
                    status: 200,
                    headers: [
                        ("Content-Type", "text/plain"), ("X-Upload", "done"), ("Content-Length", String(body.count)),
                    ]
                ) + body,
                counted: false
            )
        case .ietf:
            status = 204
            isSent = io.send(
                Self.head(status: 204, headers: [("Upload-Offset", String(held.data.count))]),
                counted: false
            )
        case .tus:
            status = 204
            isSent = io.send(
                Self.head(
                    status: 204,
                    headers: [("Upload-Offset", String(held.data.count)), ("Tus-Resumable", "1.0.0")]
                ),
                counted: false
            )
        }

        record(head, bodyLength: outcome.length, isIntact: true, isComplete: true, status: status)
        return isSent
    }

    // MARK: - Bookkeeping (called from `TransferServerIO`)

    fileprivate func didSendBody(_ count: Int) {
        lock.withLock { _bodyBytesWritten += count }
    }

    fileprivate func didReceiveUpload(_ count: Int) {
        lock.withLock { _uploadBytesReceived += count }
    }

    fileprivate func didStall() {
        lock.withLock { _stalledConnections += 1 }
    }

    fileprivate var currentStallTimeout: Double? {
        lock.withLock { _stallTimeout }
    }

    private func record(
        _ head: TransferServerIO.Head,
        bodyLength: Int,
        isIntact: Bool,
        isComplete: Bool,
        status: Int
    ) {
        let request = ReceivedRequest(
            method: head.method,
            path: head.path,
            headers: head.headers,
            bodyLength: bodyLength,
            isBodyIntact: isIntact,
            isBodyComplete: isComplete,
            status: status
        )

        lock.withLock { _requests.append(request) }
    }

    // MARK: - Private static methods

    private static func head(status: Int, headers: [(String, String)]) -> [UInt8] {
        let reason: String

        switch status {
        case 200: reason = "OK"
        case 206: reason = "Partial Content"
        case 201: reason = "Created"
        case 204: reason = "No Content"
        case 307: reason = "Temporary Redirect"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 409: reason = "Conflict"
        case 416: reason = "Range Not Satisfiable"
        default: reason = "Status"
        }

        let lines = ["HTTP/1.1 \(status) \(reason)"] + headers.map { "\($0.0): \($0.1)" }
        return Array((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    /// `N` from `bytes=N-`; anything else (a closed range, several ranges) is ignored, like a
    /// server that only implements what these tests ask for.
    private static func rangeStart(_ value: String?) -> Int? {
        guard let value, value.hasPrefix("bytes="), value.hasSuffix("-") else {
            return nil
        }

        return Int(value.dropFirst("bytes=".count).dropLast())
    }
}

package struct TransferServerError: Error, Sendable {
    package let code: Int32
}

/// Runs `body` against a fresh ``TransferServer``, stopping it (and every connection it still
/// has) afterwards, whichever way `body` ends.
package func withTransferServer<Result>(
    _ resource: TransferServer.Resource,
    perform body: (TransferServer) async throws -> Result
) async throws -> Result {
    let server = try TransferServer(resource: resource)

    do {
        let result = try await body(server)
        await server.stop()
        return result
    } catch {
        await server.stop()
        throw error
    }
}

// MARK: - IO

/// Blocking reads and writes on one connection, with the server's stall timeout applied to each.
private struct TransferServerIO {

    struct Head {
        let method: String
        let path: String
        let headers: [(name: String, value: String)]

        func header(_ name: String) -> String? {
            headers.first { $0.name.lowercased() == name.lowercased() }?.value
        }
    }

    struct BodyOutcome {
        let length: Int
        let isIntact: Bool
        let isComplete: Bool
    }

    let connection: Int32
    let server: TransferServer
    private var buffer: [UInt8] = []

    init(connection: Int32, server: TransferServer) {
        self.connection = connection
        self.server = server
    }

    mutating func readHead() -> Head? {
        let terminator = Array("\r\n\r\n".utf8)

        while true {
            if let range = firstRange(of: terminator) {
                let text = String(decoding: buffer[0..<range.lowerBound], as: UTF8.self)
                buffer.removeFirst(range.upperBound)

                let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
                let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []

                let headers = lines.dropFirst().compactMap { line -> (name: String, value: String)? in
                    guard let colon = line.firstIndex(of: ":") else {
                        return nil
                    }

                    let value = line[line.index(after: colon)...].drop(while: { $0 == " " })
                    return (String(line[..<colon]), String(value))
                }

                return Head(
                    method: requestLine.first ?? "",
                    path: requestLine.count > 1 ? requestLine[1] : "",
                    headers: headers
                )
            }

            // No stall timeout while idle between requests: that's keep-alive, not a stall.
            guard fill(stallTimeout: nil) else {
                return nil
            }
        }
    }

    /// - Parameter sink: Given every piece of the body as it arrives, in place of checking it
    ///   against the pattern of ``TransferServer/uploadByte(at:)``.
    mutating func readBody(
        _ head: Head,
        dropAfter: Int?,
        sink: ((ArraySlice<UInt8>) -> Void)? = nil
    ) -> BodyOutcome {
        var position = 0
        var isIntact = true

        func consume(_ bytes: ArraySlice<UInt8>) {
            if let sink {
                sink(bytes)
            } else if !bytes.elementsEqual(TransferServer.uploadBody(from: position, count: bytes.count)) {
                isIntact = false
            }

            position += bytes.count
            server.didReceiveUpload(bytes.count)
            server.onUploadProgress?(position)

            let delay = server.uploadReadDelay

            if delay > .zero {
                usleep(delay)
            }
        }

        if let contentLength = head.header("Content-Length").flatMap({ Int($0) }) {
            var remaining = contentLength

            while remaining > 0 {
                if let dropAfter, position >= dropAfter {
                    return BodyOutcome(length: position, isIntact: isIntact, isComplete: false)
                }

                if buffer.isEmpty, !fill(stallTimeout: server.currentStallTimeout) {
                    return BodyOutcome(length: position, isIntact: isIntact, isComplete: false)
                }

                var taken = min(remaining, buffer.count)

                if let dropAfter {
                    taken = min(taken, dropAfter - position)
                }

                consume(buffer[0..<taken])
                buffer.removeFirst(taken)
                remaining -= taken
            }

            return BodyOutcome(length: position, isIntact: isIntact, isComplete: true)
        }

        guard head.header("Transfer-Encoding")?.lowercased() == "chunked" else {
            return BodyOutcome(length: 0, isIntact: true, isComplete: true)
        }

        while true {
            guard
                let line = readLine(),
                let size = Int(line.split(separator: ";").first.map(String.init) ?? "", radix: 16)
            else {
                return BodyOutcome(length: position, isIntact: isIntact, isComplete: false)
            }

            if size == 0 {
                while let trailer = readLine(), !trailer.isEmpty {}
                return BodyOutcome(length: position, isIntact: isIntact, isComplete: true)
            }

            var remaining = size

            while remaining > 0 {
                if let dropAfter, position >= dropAfter {
                    return BodyOutcome(length: position, isIntact: isIntact, isComplete: false)
                }

                if buffer.isEmpty, !fill(stallTimeout: server.currentStallTimeout) {
                    return BodyOutcome(length: position, isIntact: isIntact, isComplete: false)
                }

                var taken = min(remaining, buffer.count)

                if let dropAfter {
                    taken = min(taken, dropAfter - position)
                }

                consume(buffer[0..<taken])
                buffer.removeFirst(taken)
                remaining -= taken
            }

            guard readLine() != nil else {
                return BodyOutcome(length: position, isIntact: isIntact, isComplete: false)
            }
        }
    }

    /// - Parameter counted: Body bytes, as opposed to framing, are added to the server's count as
    ///   the kernel accepts them.
    func send(_ bytes: [UInt8], counted: Bool) -> Bool {
        var offset = 0

        while offset < bytes.count {
            if let stallTimeout = server.currentStallTimeout, !waitUntil(Int16(POLLOUT), timeout: stallTimeout) {
                server.didStall()
                return false
            }

            #if canImport(Darwin)
            let flags: Int32 = 0
            #else
            let flags = Int32(MSG_NOSIGNAL)
            #endif

            let sent = bytes.withUnsafeBytes {
                Glue.send(connection, $0.baseAddress! + offset, bytes.count - offset, flags)
            }

            guard sent > 0 else {
                return false
            }

            offset += sent

            if counted {
                server.didSendBody(sent)
            }
        }

        return true
    }

    // MARK: - Private methods

    private mutating func readLine() -> String? {
        let terminator = Array("\r\n".utf8)

        while true {
            if let range = firstRange(of: terminator) {
                let line = String(decoding: buffer[0..<range.lowerBound], as: UTF8.self)
                buffer.removeFirst(range.upperBound)
                return line
            }

            guard fill(stallTimeout: server.currentStallTimeout) else {
                return nil
            }
        }
    }

    private mutating func fill(stallTimeout: Double?) -> Bool {
        if let stallTimeout, !waitUntil(Int16(POLLIN), timeout: stallTimeout) {
            server.didStall()
            return false
        }

        var chunk = [UInt8](repeating: 0, count: 16_384)
        let count = chunk.withUnsafeMutableBytes { Glue.recv(connection, $0.baseAddress!, $0.count, 0) }

        guard count > 0 else {
            return false
        }

        buffer += chunk[0..<count]
        return true
    }

    /// `false` if `events` didn't become ready within `timeout` seconds.
    private func waitUntil(_ events: Int16, timeout: Double) -> Bool {
        var descriptor = pollfd(fd: connection, events: events, revents: 0)
        return poll(&descriptor, 1, Int32(timeout * 1_000)) > 0
    }

    private func firstRange(of pattern: [UInt8]) -> Range<Int>? {
        guard buffer.count >= pattern.count else {
            return nil
        }

        for start in 0...(buffer.count - pattern.count) where buffer[start] == pattern[0] {
            let candidate = start..<start + pattern.count

            if buffer[candidate].elementsEqual(pattern) {
                return candidate
            }
        }

        return nil
    }
}

/// The C `send`/`recv`, reachable from inside a type that declares methods of the same names.
private enum Glue {

    static func send(_ socket: Int32, _ bytes: UnsafeRawPointer, _ count: Int, _ flags: Int32) -> Int {
        #if canImport(Darwin)
        Darwin.send(socket, bytes, count, flags)
        #elseif canImport(Glibc)
        Glibc.send(socket, bytes, count, flags)
        #elseif canImport(Android)
        Android.send(socket, bytes, count, flags)
        #else
        Musl.send(socket, bytes, count, flags)
        #endif
    }

    static func recv(_ socket: Int32, _ bytes: UnsafeMutableRawPointer, _ count: Int, _ flags: Int32) -> Int {
        #if canImport(Darwin)
        Darwin.recv(socket, bytes, count, flags)
        #elseif canImport(Glibc)
        Glibc.recv(socket, bytes, count, flags)
        #elseif canImport(Android)
        Android.recv(socket, bytes, count, flags)
        #else
        Musl.recv(socket, bytes, count, flags)
        #endif
    }
}
