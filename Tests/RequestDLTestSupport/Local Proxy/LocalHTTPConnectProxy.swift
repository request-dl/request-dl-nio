//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOPosix
import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A minimal HTTP `CONNECT` proxy.
///
/// No pre-existing NIO-backend proxy round-trip fixture existed to reuse -- `ProxyTests`
/// (`RequestDLTests`) and `InternalsProxyTests` (`RequestDLInternalsTests`) only cover config
/// mapping, never an actual proxied connection. This stands in for a real forward proxy just
/// enough to prove a `CONNECT` tunnel (with optional Basic proxy authentication) actually carries
/// traffic: it accepts one `CONNECT host:port` request, optionally challenges it for
/// `Proxy-Authorization`, replies `200 Connection Established`, then relays raw bytes both ways
/// between the accepted connection and a freshly dialed one to `host:port` -- opaque after that
/// point, so it works equally for a plain or TLS-wrapped tunnel (`LocalServer` is always TLS).
///
/// Deliberately hand-parses the `CONNECT` request/writes the response as raw bytes rather than
/// using `NIOHTTP1`'s codec (`HTTPRequestDecoder`/`HTTPResponseEncoder`) removed mid-connection --
/// an earlier version did that, and removing handlers asynchronously while the client is free to
/// start writing tunnel bytes (a TLS `ClientHello`, the instant it sees the `200`) the moment the
/// response is flushed raced the removal on iOS/tvOS/watchOS/visionOS Simulators (reliably; never
/// observed on macOS): bytes meant for the tunnel could still reach the not-yet-removed
/// `HTTPRequestDecoder`, which trips `NIOAny`'s type-mismatch fatal error on anything that isn't
/// a well-formed HTTP request. One handler for the whole connection, switching mode internally
/// once the `CONNECT` is answered, has no such window -- nothing is ever removed from the pipeline.
struct LocalHTTPConnectProxy: Sendable {

    // MARK: - Internal properties

    let host = "127.0.0.1"
    let port: Int

    /// How many `CONNECT` requests this proxy has actually received, successful or not.
    ///
    /// Exists so a test can assert the proxy was genuinely used rather than the request having
    /// somehow reached its destination directly -- both `127.0.0.1` targets and system-level
    /// "bypass proxy for local addresses" rules are exactly the kind of thing that silently
    /// short-circuits proxying and would otherwise let a broken `connectionProxyDictionary`
    /// mapping pass every test for the wrong reason.
    let connectAttempts: ConnectAttemptCounter

    // MARK: - Private properties

    private let group: EventLoopGroup
    private let channel: Channel

    // MARK: - Internal static methods

    /// - Parameter requiredProxyAuthorization: The exact `Proxy-Authorization` header value a
    /// `CONNECT` request must carry (e.g. `"Basic dXNlcjpwYXNz"`). `nil` accepts every `CONNECT`
    /// unconditionally.
    static func start(requiredProxyAuthorization: String? = nil) async throws -> LocalHTTPConnectProxy {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let connectAttempts = ConnectAttemptCounter()

        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(
                    ConnectHandler(
                        group: group,
                        requiredProxyAuthorization: requiredProxyAuthorization,
                        connectAttempts: connectAttempts
                    )
                )
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()

        guard let port = channel.localAddress?.port else {
            struct MissingLocalPortError: Error {}
            throw MissingLocalPortError()
        }

        return LocalHTTPConnectProxy(port: port, connectAttempts: connectAttempts, group: group, channel: channel)
    }

    // MARK: - Internal methods

    func shutdown() async throws {
        try await channel.close()
        try await group.shutdownGracefully()
    }
}

/// Thread-safe counter incremented once per `CONNECT` request a `LocalHTTPConnectProxy` receives.
final class ConnectAttemptCounter: @unchecked Sendable {

    private let lock = Lock()
    private var _count = 0

    var count: Int {
        lock.withLock { _count }
    }

    func increment() {
        lock.withLock { _count += 1 }
    }
}

/// One instance per accepted connection. Starts in `.awaitingRequest`, hand-parsing raw bytes
/// until a full `CONNECT` request (terminated by a blank line) has arrived; once answered, flips
/// to `.relaying` and every subsequent byte is forwarded to the dialed destination channel
/// instead -- the same handler, the same pipeline position, throughout.
private final class ConnectHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum Mode {
        case awaitingRequest
        case relaying(Channel)
    }

    // MARK: - Private properties

    private let group: EventLoopGroup
    private let requiredProxyAuthorization: String?
    private let connectAttempts: ConnectAttemptCounter

    // MARK: - Unsafe properties

    private var mode: Mode = .awaitingRequest
    private var buffer: ByteBuffer = ByteBufferAllocator().buffer(capacity: 512)

    // MARK: - Inits

    init(group: EventLoopGroup, requiredProxyAuthorization: String?, connectAttempts: ConnectAttemptCounter) {
        self.group = group
        self.requiredProxyAuthorization = requiredProxyAuthorization
        self.connectAttempts = connectAttempts
    }

    // MARK: - Internal methods

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)

        switch mode {
        case .relaying(let destination):
            destination.writeAndFlush(incoming, promise: nil)

        case .awaitingRequest:
            buffer.writeBuffer(&incoming)
            processBufferedRequest(context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if case .relaying(let destination) = mode {
            destination.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    // MARK: - Private methods

    /// A `CONNECT` request has no body -- the blank line ending its headers also ends the
    /// request, so waiting for `"\r\n\r\n"` is sufficient (no `Content-Length`/chunked handling
    /// needed, unlike a general HTTP/1.1 parser).
    private func processBufferedRequest(context: ChannelHandlerContext) {
        let bytes = buffer.readableBytesView
        guard let headerEndRange = Self.firstRange(of: Array("\r\n\r\n".utf8), in: bytes) else {
            return
        }

        let headerBytes = bytes[bytes.startIndex..<headerEndRange.lowerBound]
        let text = String(decoding: headerBytes, as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")

        guard
            let requestLine = lines.first,
            !requestLine.isEmpty
        else {
            writeAndClose(context: context, statusLine: "400 Bad Request")
            return
        }

        let requestLineParts = requestLine.split(separator: " ")

        guard requestLineParts.count >= 2, requestLineParts[0] == "CONNECT" else {
            writeAndClose(context: context, statusLine: "400 Bad Request")
            return
        }

        connectAttempts.increment()

        let authority = String(requestLineParts[1])
        let headerLines = lines.dropFirst().filter { !$0.isEmpty }

        if let requiredProxyAuthorization {
            let proxyAuthorization = headerLines.lazy.compactMap { line -> String? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].caseInsensitiveCompare("Proxy-Authorization") else {
                    return nil
                }
                return parts[1].trimmingLeadingAndTrailingSpaces()
            }.first

            guard proxyAuthorization == requiredProxyAuthorization else {
                writeAndClose(
                    context: context,
                    statusLine: "407 Proxy Authentication Required",
                    extraHeaderLines: ["Proxy-Authenticate: Basic realm=\"proxy\""],
                    keepAlive: true
                )
                return
            }
        }

        let components = authority.split(separator: ":", maxSplits: 1)

        guard components.count == 2, let port = Int(components[1]) else {
            writeAndClose(context: context, statusLine: "400 Bad Request")
            return
        }

        let host = String(components[0])

        // Anything the client pipelined onto the same TCP segment as the `CONNECT` request
        // itself (a TLS `ClientHello`, in principle) is tunnel data, not more request to parse --
        // held onto and relayed once the tunnel exists, not dropped. `headerEndRange` is already
        // in `buffer`'s own (absolute) index space, same as `ByteBufferView`'s throughout.
        let leftoverStart = headerEndRange.lowerBound + 4
        let leftover = buffer.getSlice(at: leftoverStart, length: buffer.writerIndex - leftoverStart)
        buffer.clear()

        startRelay(host: host, port: port, leftover: leftover, context: context)
    }

    private func writeAndClose(
        context: ChannelHandlerContext,
        statusLine: String,
        extraHeaderLines: [String] = [],
        keepAlive: Bool = false
    ) {
        let headerLines = (["HTTP/1.1 \(statusLine)"] + extraHeaderLines).joined(separator: "\r\n")
        let response = headerLines + "\r\n\r\n"

        var out = context.channel.allocator.buffer(capacity: response.utf8.count)
        out.writeString(response)

        context.writeAndFlush(wrapOutboundOut(out)).whenComplete { _ in
            if !keepAlive {
                context.close(promise: nil)
            }
        }

        buffer.clear()
    }

    /// Dials `host:port`, answers the `CONNECT` with `200`, and flips `mode` to `.relaying` --
    /// from here on `channelRead` forwards to `outboundChannel` directly, and a lightweight
    /// closure-based handler on `outboundChannel`'s own pipeline forwards the other direction.
    /// Nothing is ever added to or removed from *this* channel's pipeline.
    private func startRelay(host: String, port: Int, leftover: ByteBuffer?, context: ChannelHandlerContext) {
        let clientChannel = context.channel

        ClientBootstrap(group: group).connect(host: host, port: port).whenComplete { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure:
                clientChannel.close(promise: nil)

            case .success(let outboundChannel):
                outboundChannel.pipeline.addHandler(OutboundRelayHandler(to: clientChannel)).whenComplete {
                    addResult in
                    switch addResult {
                    case .failure:
                        clientChannel.close(promise: nil)
                        outboundChannel.close(promise: nil)

                    case .success:
                        clientChannel.eventLoop.execute {
                            self.mode = .relaying(outboundChannel)

                            var out = clientChannel.allocator.buffer(capacity: 39)
                            out.writeString("HTTP/1.1 200 Connection Established\r\n\r\n")
                            clientChannel.writeAndFlush(out, promise: nil)

                            if let leftover, leftover.readableBytes > 0 {
                                outboundChannel.writeAndFlush(leftover, promise: nil)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private static methods

    /// `ByteBufferView` has no built-in subsequence search (that's `swift-algorithms`, not a
    /// dependency here) -- header sizes here are a few hundred bytes at most, so the naive scan
    /// is more than fast enough.
    private static func firstRange(of pattern: [UInt8], in view: ByteBufferView) -> Range<Int>? {
        guard !pattern.isEmpty, view.count >= pattern.count else {
            return nil
        }

        var index = view.startIndex
        let lastPossibleStart = view.endIndex - pattern.count

        while index <= lastPossibleStart {
            var matched = true

            for offset in 0..<pattern.count where view[index + offset] != pattern[offset] {
                matched = false
                break
            }

            if matched {
                return index..<(index + pattern.count)
            }

            index += 1
        }

        return nil
    }
}

/// The destination side of a tunnel: forwards every byte read back to the original client
/// connection, and closes it once the destination goes away.
private final class OutboundRelayHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let destination: Channel

    init(to destination: Channel) {
        self.destination = destination
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        destination.writeAndFlush(unwrapInboundIn(data), promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        destination.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

extension StringProtocol {
    fileprivate func caseInsensitiveCompare<S: StringProtocol>(_ other: S) -> Bool {
        self.lowercased() == other.lowercased()
    }

    /// `trimmingCharacters(in: .whitespaces)` needs full `Foundation` (`CharacterSet`), not
    /// available under `FoundationEssentials` on Linux -- this header-value trim only ever needs
    /// to strip plain ASCII spaces, so it doesn't need `Foundation` at all.
    fileprivate func trimmingLeadingAndTrailingSpaces() -> String {
        var value = Substring(self)
        while value.first == " " { value.removeFirst() }
        while value.last == " " { value.removeLast() }
        return String(value)
    }
}
