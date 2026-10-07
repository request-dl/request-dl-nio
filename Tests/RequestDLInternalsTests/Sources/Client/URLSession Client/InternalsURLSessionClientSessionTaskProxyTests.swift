//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Darwin
import Foundation
import SwiftAsyncStream
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

/// Proxy authentication through `Internals.URLSessionClient`'s `SessionTask` path, which reads the
/// response through `URLSession.bytes(for:delegate:)` rather than a plain data/upload task.
///
/// `bytes(for:delegate:)` only forwards *task*-level delegate callbacks to `TaskDelegate`, and a
/// proxy's `407` on a `CONNECT` reaches it as exactly one of those
/// (`urlSession(_:task:didReceive:completionHandler:)`, with `protectionSpace.isProxy()`). These
/// tests prove the challenge actually arrives and is answered there, not merely that a request
/// happens to succeed: `AuthenticatingProxy` records the `Proxy-Authorization` header of every
/// request it gets, so each successful test also asserts the first attempt went out *without*
/// credentials and was challenged, and that what finally got through is exactly the configured
/// credential.
///
/// Unlike `InternalsURLSessionClientProxyTests`, these genuinely run on macOS too: the request's
/// host is `proxied.requestdl.test`, not `localhost`, so the OS doesn't bypass the proxy for it,
/// and it never has to resolve, since the proxy alone decides where the connection really goes.
/// The fixture is plain BSD sockets, so they also run under `--disable-default-traits`.
///
/// Two behaviours pinned here are properties of `URLSession`'s proxy authentication itself, not
/// of this path: both reproduce identically through the buffered `execute(request:delegate:)`
/// overload's plain `dataTask`. See
/// `forwardedRequest_throughAnAuthenticatingProxy_getsThe407WithoutAChallenge` and
/// `connectTunnel_withoutConfiguredAuthorization_endsByTheRequestTimeout`.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsURLSessionClientSessionTaskProxyTests {

    private static let username = "proxy-user"
    private static let password = "proxy-pass"

    private static var expectedAuthorization: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }

    private static let proxiedHost = "proxied.requestdl.test"

    /// Which of `Internals.URLSessionClient`'s request paths a test drives: the `SessionTask` one,
    /// over `bytes(for:delegate:)`, or the buffered `execute(request:delegate:)`, over a plain
    /// `dataTask`.
    enum RequestPath: Sendable, CustomTestStringConvertible {
        case sessionTask
        case buffered

        var testDescription: String {
            switch self {
            case .sessionTask: "sessionTask"
            case .buffered: "buffered"
            }
        }
    }

    /// An HTTPS request tunnelled through `CONNECT` to `LocalServer`, with `.basic` credentials.
    @Test
    func connectTunnel_withBasicAuthorization_answersTheProxyChallenge() async throws {
        try await assertTunnelledRoundTrip(authorization: .basic(username: Self.username, password: Self.password))
    }

    /// The same, with the credentials given pre-encoded.
    @Test
    func connectTunnel_withBasicRawCredentials_answersTheProxyChallenge() async throws {
        let raw = Data("\(Self.username):\(Self.password)".utf8).base64EncodedString()
        try await assertTunnelledRoundTrip(authorization: .basicRawCredentials(raw))
    }

    /// A `POST` with a file-backed body (`existingUploadFile`, sent as an `httpBodyStream` on
    /// this path) through the authenticated tunnel: the destination has to receive all of it.
    @Test
    func connectTunnel_withAFileBackedUpload_deliversTheWholeBody() async throws {
        let payload = Data((0..<2_000_003).map { UInt8(truncatingIfNeeded: $0 &* 11) })

        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "uploaded"), at: uri)
        defer { localServer.cleanup(at: uri) }

        try await withTemporaryFileURL("proxied-upload.bin") { fileURL in
            try payload.write(to: fileURL)

            try await withAuthenticatingProxy(
                requiredAuthorization: Self.expectedAuthorization,
                upstreamPort: Int(LocalServer.Configuration.standard.port)
            ) { proxy in
                // Given
                let client = try Self.client(
                    through: proxy,
                    authorization: .basic(username: Self.username, password: Self.password)
                )
                var request = URLRequest(url: try #require(URL(string: "https://\(Self.proxiedHost):443\(uri)")))
                request.httpMethod = "POST"

                // When
                let task = try await client.execute(
                    request: request,
                    streaming: emptyBody(),
                    readingMode: .length(1_024),
                    uploadingBytes: payload.count,
                    decompression: .disabled,
                    cache: nil,
                    logger: nil,
                    delegate: AcceptAnyServerTrustDelegate(),
                    existingUploadFile: fileURL
                )

                let (status, body) = try await drain(task)

                // Then
                #expect(status == 200)

                let decoded = try HTTPResult<String>(body)
                #expect(decoded.receivedBytes == payload.count)
                #expect(decoded.response == "uploaded")

                let requests = proxy.requests
                #expect(requests.first?.proxyAuthorization == nil)
                #expect(requests.last?.proxyAuthorization == Self.expectedAuthorization)
                try await eventually { !client.isRunning }
            }
        }
    }

    /// Back pressure holds through a proxy too: a reader that stops leaves the proxy's own
    /// connection to the client stalled. (A forwarded plain-HTTP request, answered by the proxy
    /// itself, so the proxy is what counts the bytes; see the next test for why this proxy doesn't
    /// also require credentials.)
    @Test
    func forwardedDownload_readerStops_pausesTheConnectionThroughTheProxy() async throws {
        let totalBytes = 64 * 1_048_576

        try await withAuthenticatingProxy(requiredAuthorization: nil, cannedBodySize: totalBytes) { proxy in
            // Given
            let client = try Self.client(through: proxy, authorization: nil)
            let url = try #require(URL(string: "http://\(Self.proxiedHost):8080/download"))

            let task = try await client.execute(
                request: URLRequest(url: url),
                readingMode: .length(65_536),
                uploadingBytes: .zero,
                decompression: .disabled,
                cache: nil,
                logger: nil
            )

            var download: Internals.DownloadStep?
            for try await step in task.response {
                if case .download(let step) = step {
                    download = step
                }
            }

            let step = try #require(download)
            var iterator = step.bytes.makeAsyncIterator()
            _ = try await iterator.next()

            // When: the reader stops.
            let written = try await proxy.settledBodyBytesWritten()

            // Then: through the proxy, and stalled far short of the body.
            #expect(step.head.status.code == 200)
            #expect(proxy.requests.map(\.target) == ["http://\(Self.proxiedHost):8080/download"])
            #expect(written < totalBytes / 4)

            task.seed()
            try await eventually { !client.isRunning }
        }
    }

    /// Pins a limitation of `URLSession` itself, not of this path: for a plain-HTTP destination,
    /// sent to the proxy as a forwarded request rather than a `CONNECT`, `URLSession` never raises
    /// a proxy authentication challenge at all. `TaskDelegate` never hears of the `407`, so the
    /// configured credentials are never sent, and the `407` comes back as the response. Identical
    /// through the buffered `execute(request:delegate:)` overload's plain `dataTask`, observed
    /// side by side; the NIO executor, which sends `Proxy-Authorization` up front, has no such gap.
    ///
    /// What this asserts is that it ends promptly and visibly (one request, the proxy's own
    /// `407`) rather than hanging or appearing to succeed.
    @Test
    func forwardedRequest_throughAnAuthenticatingProxy_getsThe407WithoutAChallenge() async throws {
        try await withAuthenticatingProxy(
            requiredAuthorization: Self.expectedAuthorization,
            cannedBodySize: 1_024
        ) { proxy in
            // Given
            let client = try Self.client(
                through: proxy,
                authorization: .basic(username: Self.username, password: Self.password)
            )
            let url = try #require(URL(string: "http://\(Self.proxiedHost):8080/forwarded"))

            // When
            let (status, body) = try await completing(within: 30) {
                try await drain(
                    try await client.execute(
                        request: URLRequest(url: url),
                        readingMode: .length(1_024),
                        uploadingBytes: .zero,
                        decompression: .disabled,
                        cache: nil,
                        logger: nil
                    )
                )
            }

            // Then
            #expect(status == 407)
            #expect(body.isEmpty)
            #expect(proxy.requests.map(\.proxyAuthorization) == [nil])
            try await eventually { !client.isRunning }
        }
    }

    /// The proxy rejects the configured credentials. `TaskDelegate` answers the first challenge
    /// with them and cancels any repeat, reporting `ProxyAuthenticationFailedError`.
    ///
    /// Answering every repeat with the same rejected credential would send the proxy 81-340
    /// `CONNECT`s within a fraction of a second before `URLSession` gave up on its own. Leaving
    /// the repeat to default handling instead fails fast most of the time but, about one run in
    /// three, waits out the whole request timeout, which is why the timeout here is far longer
    /// than this is allowed to take.
    @Test(arguments: [RequestPath.sessionTask, .buffered])
    func connectTunnel_withWrongCredentials_failsFastWithoutRetrying(path: RequestPath) async throws {
        try await withAuthenticatingProxy(
            requiredAuthorization: Self.expectedAuthorization,
            upstreamPort: Int(LocalServer.Configuration.standard.port)
        ) { proxy in
            // Given
            let client = try Self.client(
                through: proxy,
                authorization: .basic(username: Self.username, password: "wrong"),
                requestTimeout: 60
            )
            let url = try #require(URL(string: "https://\(Self.proxiedHost):443/unreachable"))
            let start = Date()

            // When
            let error = try await completing(within: 10) { () -> (any Error)? in
                do {
                    switch path {
                    case .sessionTask:
                        _ = try await drain(
                            try await client.execute(
                                request: URLRequest(url: url),
                                readingMode: .length(1_024),
                                uploadingBytes: .zero,
                                decompression: .disabled,
                                cache: nil,
                                logger: nil,
                                delegate: AcceptAnyServerTrustDelegate()
                            )
                        )
                    case .buffered:
                        _ = try await client.execute(
                            request: URLRequest(url: url),
                            delegate: AcceptAnyServerTrustDelegate()
                        )
                    }

                    return nil
                } catch {
                    return error
                }
            }

            // Then
            #expect(error is Internals.URLSessionClient.ProxyAuthenticationFailedError)
            #expect(Date().timeIntervalSince(start) < 5)
            #expect(proxy.requests.first?.proxyAuthorization == nil)
            #expect(proxy.requests.count <= 5)
            #expect(proxy.requests.allSatisfy { $0.proxyAuthorization != Self.expectedAuthorization })
            try await eventually { !client.isRunning }
        }
    }

    /// Pins a limitation of `URLSession` itself, not of this path: the proxy demands credentials
    /// and none are configured, so `TaskDelegate` leaves the challenge to `URLSession`'s default
    /// handling, deliberately, since that is also what lets credentials the system itself holds
    /// for a proxy be used. With none there either, on macOS `URLSession` neither fails nor
    /// retries: the request waits out `timeoutIntervalForRequest` and only then fails. Identical
    /// through the buffered `execute(request:delegate:)` overload's plain `dataTask` (31s against
    /// a 30s timeout, observed side by side). The iOS Simulator fails it at once instead.
    ///
    /// Asserted with a short request timeout: it has to end by then, not hang, and never reach the
    /// destination.
    @Test
    func connectTunnel_withoutConfiguredAuthorization_endsByTheRequestTimeout() async throws {
        try await withAuthenticatingProxy(
            requiredAuthorization: Self.expectedAuthorization,
            upstreamPort: Int(LocalServer.Configuration.standard.port)
        ) { proxy in
            // Given
            let client = try Self.client(through: proxy, authorization: nil, requestTimeout: 3)

            // When
            let outcome = try await Self.outcome(of: client, timeout: 20)

            // Then
            #expect(outcome == "failed")
            #expect(proxy.requests.map(\.proxyAuthorization) == [nil])
            try await eventually { !client.isRunning }
        }
    }

    #if canImport(NIOCore)
    /// `InternalsURLSessionClientSOCKSProxyTests`' round trip, through this path. Same fixture,
    /// same `localhost` destination, so the same macOS/Catalyst-only known issue (the OS bypasses
    /// a configured proxy for `localhost`); it genuinely runs on the Simulators.
    @Test
    func socksProxy_tunnelsUnlessPlatformBypassesLocalhost() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello Through The SOCKS Tunnel"

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: output), at: uri)
        defer { localServer.cleanup(at: uri) }

        let proxy = try await LocalSOCKSProxy.start()

        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            proxy: Internals.Proxy(host: proxy.host, port: proxy.port, connection: .socks, authorization: nil)
        )

        // When
        let task = try await client.execute(
            request: URLRequest(url: try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))),
            readingMode: .length(1_024),
            uploadingBytes: .zero,
            decompression: .disabled,
            cache: nil,
            logger: nil,
            delegate: AcceptAnyServerTrustDelegate()
        )

        let (status, body) = try await drain(task)

        // Then
        #expect(status == 200)
        #expect(try HTTPResult<String>(body).response == output)

        withKnownIssue(
            "macOS/Catalyst bypass a configured proxy for localhost -- see InternalsURLSessionClientSOCKSProxyTests",
            {
                #expect(proxy.connectAttempts.count >= 1)
            },
            when: {
                #if os(macOS) || targetEnvironment(macCatalyst)
                return true
                #else
                return false
                #endif
            }
        )

        try await proxy.shutdown()
    }
    #endif

    // MARK: - Helpers

    private static func client(
        through proxy: AuthenticatingProxy,
        authorization: Internals.Proxy.Authorization?,
        requestTimeout: TimeInterval = simulatorAffectedURLSessionRequestTimeout
    ) throws -> Internals.URLSessionClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout

        return try Internals.URLSessionClient(
            configuration: configuration,
            proxy: Internals.Proxy(
                host: "127.0.0.1",
                port: proxy.port,
                connection: .http,
                authorization: authorization
            )
        )
    }

    /// Runs a `GET` for the tunnelled destination to its end: `"status N"`, or `"failed"`.
    private static func outcome(of client: Internals.URLSessionClient, timeout: Double) async throws -> String {
        let url = try #require(URL(string: "https://\(Self.proxiedHost):443/unreachable"))

        return try await completing(within: timeout) {
            do {
                let (status, _) = try await drain(
                    try await client.execute(
                        request: URLRequest(url: url),
                        readingMode: .length(1_024),
                        uploadingBytes: .zero,
                        decompression: .disabled,
                        cache: nil,
                        logger: nil,
                        delegate: AcceptAnyServerTrustDelegate()
                    )
                )

                return "status \(status.map(String.init) ?? "none")"
            } catch {
                return "failed"
            }
        }
    }

    private func assertTunnelledRoundTrip(authorization: Internals.Proxy.Authorization) async throws {
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello Through The Authenticated Tunnel"

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: output), at: uri)
        defer { localServer.cleanup(at: uri) }

        try await withAuthenticatingProxy(
            requiredAuthorization: Self.expectedAuthorization,
            upstreamPort: Int(LocalServer.Configuration.standard.port)
        ) { proxy in
            // Given
            let client = try Self.client(through: proxy, authorization: authorization)
            let url = try #require(URL(string: "https://\(Self.proxiedHost):443\(uri)"))

            // When
            let task = try await client.execute(
                request: URLRequest(url: url),
                readingMode: .length(1_024),
                uploadingBytes: .zero,
                decompression: .disabled,
                cache: nil,
                logger: nil,
                delegate: AcceptAnyServerTrustDelegate()
            )

            let (status, body) = try await drain(task)

            // Then: through the proxy, not around it, and only after it challenged.
            #expect(status == 200)
            #expect(try HTTPResult<String>(body).response == output)

            let requests = proxy.requests
            #expect(requests.allSatisfy { $0.method == "CONNECT" && $0.target == "\(Self.proxiedHost):443" })
            #expect(requests.first?.proxyAuthorization == nil)
            #expect(requests.last?.proxyAuthorization == Self.expectedAuthorization)
            #expect(requests.count == 2)

            try await eventually { !client.isRunning }
        }
    }
}

// MARK: - Body helpers

private func emptyBody() -> AsyncStream<Internals.Bytes> {
    let (stream, continuation) = AsyncStream<Internals.Bytes>.makeStream()
    continuation.finish()
    return stream
}

/// Reads `task` to its end, returning the status and the body.
private func drain(_ task: SessionTask) async throws -> (UInt?, Data) {
    var status: UInt?
    var body = Data()

    for try await step in task.response {
        guard case .download(let download) = step else { continue }
        status = download.head.status.code

        for try await chunk in download.bytes {
            body.append(chunk)
        }
    }

    return (status, body)
}

/// Test-only stand-in for the real client's own TLS challenge handling: `LocalServer` is always
/// TLS-terminated with a throwaway self-signed certificate (issued for `localhost`, so it doesn't
/// match `proxied.requestdl.test` either).
private final class AcceptAnyServerTrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

// MARK: - Proxy

/// A minimal forward proxy on plain BSD sockets that can require Basic `Proxy-Authorization`.
///
/// - When `requiredAuthorization` is set, a request without exactly that gets `407` with a
///   `Proxy-Authenticate: Basic` challenge, and the connection is closed.
/// - An authorized `CONNECT` is answered `200 Connection Established` and relayed, raw, to
///   `127.0.0.1:upstreamPort` (whatever host the client asked for), so the client can use a
///   host name the OS won't bypass the proxy for, and that never has to resolve.
/// - An authorized forwarded (absolute-form) request is answered by the proxy itself, with
///   `cannedBodySize` bytes of body, written with blocking `send(2)` into a small send buffer and
///   counted, the same way `InternalsURLSessionClientBackPressureTests`' server counts them.
///
/// Every request is recorded, credentials included, so tests can assert the challenge really
/// happened rather than infer it from success.
private final class AuthenticatingProxy: @unchecked Sendable {

    struct Request: Sendable {
        let method: String
        let target: String
        let proxyAuthorization: String?
        let bodyLength: Int
    }

    let port: Int

    var requests: [Request] {
        lock.withLock { _requests }
    }

    var bodyBytesWritten: Int {
        lock.withLock { _bodyBytesWritten }
    }

    private let listener: Int32
    /// `nil` admits every request.
    private let requiredAuthorization: String?
    private let upstreamPort: Int
    private let cannedBodySize: Int
    private let lock = Lock()

    private var _requests: [Request] = []
    private var _bodyBytesWritten = 0
    private var _isStopped = false
    private var _isFinished = false
    private var _connections: Set<Int32> = []

    fileprivate var isFinished: Bool {
        lock.withLock { _isFinished }
    }

    init(requiredAuthorization: String?, upstreamPort: Int, cannedBodySize: Int) throws {
        self.requiredAuthorization = requiredAuthorization
        self.upstreamPort = upstreamPort
        self.cannedBodySize = cannedBodySize

        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let isListening = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, length) == 0 && listen(listener, 16) == 0 && getsockname(listener, $0, &length) == 0
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
            acceptLoop()
        }
    }

    /// Waits for the count of body bytes the kernel accepted to stop moving for half a second.
    func settledBodyBytesWritten() async throws -> Int {
        var last = -1
        var quietPolls = 0

        for _ in 0..<3_000 {
            let current = bodyBytesWritten

            if current == cannedBodySize {
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

        return bodyBytesWritten
    }

    fileprivate func stop() {
        let connections = lock.withLock { () -> Set<Int32> in
            _isStopped = true
            return _connections
        }

        for connection in connections {
            shutdown(connection, SHUT_RDWR)
        }
    }

    // MARK: - Serving

    private func acceptLoop() {
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

            var enabled: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
            track(connection)

            Thread.detachNewThread { [self] in
                serve(connection)
            }
        }
    }

    private func track(_ connection: Int32) {
        lock.withLock { _ = _connections.insert(connection) }
    }

    private func untrackAndClose(_ connection: Int32) {
        lock.withLock { _ = _connections.remove(connection) }
        close(connection)
    }

    private func serve(_ connection: Int32) {
        var reader = SocketReader(connection: connection)

        while let head = reader.readHead() {
            let lines = head.components(separatedBy: "\r\n")
            let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []

            guard requestLine.count >= 2 else {
                break
            }

            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
            }

            let method = requestLine[0]
            let bodyLength = reader.skipBody(headers: headers) ?? 0
            let authorization = headers["proxy-authorization"]

            lock.withLock {
                _requests.append(
                    .init(
                        method: method,
                        target: requestLine[1],
                        proxyAuthorization: authorization,
                        bodyLength: bodyLength
                    )
                )
            }

            guard requiredAuthorization == nil || authorization == requiredAuthorization else {
                let challenge =
                    "HTTP/1.1 407 Proxy Authentication Required\r\n"
                    + "Proxy-Authenticate: Basic realm=\"requestdl-test\"\r\n"
                    + "Content-Length: 0\r\nConnection: close\r\n\r\n"
                _ = sendAll(connection, Array(challenge.utf8))
                break
            }

            if method == "CONNECT" {
                relay(connection, leftover: reader.takeBuffered())
                return
            }

            guard answerForwarded(connection) else {
                break
            }
        }

        untrackAndClose(connection)
    }

    /// Answers an authorized forwarded request with the canned body.
    private func answerForwarded(_ connection: Int32) -> Bool {
        var sendBuffer: Int32 = 32_768
        setsockopt(connection, SOL_SOCKET, SO_SNDBUF, &sendBuffer, socklen_t(MemoryLayout<Int32>.size))

        let head =
            "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
            + "Content-Length: \(cannedBodySize)\r\n\r\n"

        guard sendAll(connection, Array(head.utf8)) else {
            return false
        }

        let chunk = [UInt8](repeating: 0x5A, count: 65_536)
        var offset = 0

        while offset < cannedBodySize {
            let count = min(chunk.count, cannedBodySize - offset)

            guard sendAll(connection, Array(chunk[0..<count]), countingBody: true) else {
                return false
            }

            offset += count
        }

        return true
    }

    /// Relays raw bytes between `connection` and a fresh connection to `localhost:upstreamPort`.
    private func relay(_ connection: Int32, leftover: [UInt8]) {
        guard
            let upstream = Self.connectToLocalhost(port: upstreamPort),
            sendAll(connection, Array("HTTP/1.1 200 Connection Established\r\n\r\n".utf8))
        else {
            untrackAndClose(connection)
            return
        }

        track(upstream)

        if !leftover.isEmpty {
            _ = sendAll(upstream, leftover)
        }

        Thread.detachNewThread { [self] in
            pipe(from: upstream, to: connection)
            untrackAndClose(upstream)
        }

        pipe(from: connection, to: upstream)
        untrackAndClose(connection)
    }

    /// `LocalServer` binds `localhost` by name, which may be `::1`, `127.0.0.1` or both depending on
    /// the resolver, so every address it resolves to is tried in turn.
    private static func connectToLocalhost(port: Int) -> Int32? {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM

        var results: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo("localhost", String(port), &hints, &results) == 0, let results else {
            return nil
        }

        defer { freeaddrinfo(results) }

        var candidate: UnsafeMutablePointer<addrinfo>? = results

        while let info = candidate {
            let descriptor = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)

            if descriptor >= 0 {
                var enabled: Int32 = 1
                setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))

                if connect(descriptor, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                    return descriptor
                }

                close(descriptor)
            }

            candidate = info.pointee.ai_next
        }

        return nil
    }

    private func pipe(from source: Int32, to destination: Int32) {
        var buffer = [UInt8](repeating: 0, count: 16_384)

        while true {
            let count = recv(source, &buffer, buffer.count, 0)

            guard count > 0, sendAll(destination, Array(buffer[0..<count])) else {
                shutdown(destination, SHUT_WR)
                return
            }
        }
    }

    private func sendAll(_ connection: Int32, _ bytes: [UInt8], countingBody: Bool = false) -> Bool {
        var offset = 0

        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes {
                send(connection, $0.baseAddress! + offset, bytes.count - offset, 0)
            }

            guard sent > 0 else {
                return false
            }

            offset += sent

            if countingBody {
                lock.withLock { _bodyBytesWritten += sent }
            }
        }

        return true
    }
}

/// Reads HTTP/1.1 request heads and bodies off a blocking socket.
private struct SocketReader {

    let connection: Int32
    private var buffer: [UInt8] = []

    init(connection: Int32) {
        self.connection = connection
    }

    mutating func takeBuffered() -> [UInt8] {
        defer { buffer = [] }
        return buffer
    }

    mutating func readHead() -> String? {
        readUntil(Array("\r\n\r\n".utf8))
    }

    /// Skips the body `headers` describe.
    ///
    /// - Returns: Its length, or `nil` if the connection ended first.
    mutating func skipBody(headers: [String: String]) -> Int? {
        if let length = headers["content-length"].flatMap({ Int($0) }) {
            return skip(length) ? length : nil
        }

        guard headers["transfer-encoding"]?.lowercased() == "chunked" else {
            return 0
        }

        var total = 0

        while true {
            guard
                let line = readUntil(Array("\r\n".utf8)),
                let size = Int(line.split(separator: ";").first.map(String.init) ?? "", radix: 16)
            else {
                return nil
            }

            if size == .zero {
                while let trailer = readUntil(Array("\r\n".utf8)), !trailer.isEmpty {}
                return total
            }

            guard skip(size), readUntil(Array("\r\n".utf8)) != nil else {
                return nil
            }

            total += size
        }
    }

    private mutating func fill() -> Bool {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let count = recv(connection, &chunk, chunk.count, 0)

        guard count > 0 else {
            return false
        }

        buffer += chunk[0..<count]
        return true
    }

    private mutating func readUntil(_ terminator: [UInt8]) -> String? {
        while true {
            if buffer.count >= terminator.count {
                for start in 0...(buffer.count - terminator.count) {
                    let candidate = start..<start + terminator.count

                    if buffer[candidate].elementsEqual(terminator) {
                        let text = String(decoding: buffer[0..<start], as: UTF8.self)
                        buffer.removeFirst(candidate.upperBound)
                        return text
                    }
                }
            }

            guard fill() else {
                return nil
            }
        }
    }

    private mutating func skip(_ count: Int) -> Bool {
        var remaining = count

        while remaining > 0 {
            if buffer.isEmpty {
                guard fill() else { return false }
            }

            let taken = min(remaining, buffer.count)
            buffer.removeFirst(taken)
            remaining -= taken
        }

        return true
    }
}

private func withAuthenticatingProxy<Result>(
    requiredAuthorization: String?,
    upstreamPort: Int = 0,
    cannedBodySize: Int = 0,
    perform body: (AuthenticatingProxy) async throws -> Result
) async throws -> Result {
    let proxy = try AuthenticatingProxy(
        requiredAuthorization: requiredAuthorization,
        upstreamPort: upstreamPort,
        cannedBodySize: cannedBodySize
    )

    do {
        let result = try await body(proxy)
        proxy.stop()
        try await eventually { proxy.isFinished }
        return result
    } catch {
        proxy.stop()
        try? await eventually { proxy.isFinished }
        throw error
    }
}

#endif
