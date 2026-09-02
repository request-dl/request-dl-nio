//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOPosix
import SwiftAsyncStream

/// A minimal SOCKS5 proxy (RFC 1928), no authentication.
///
/// Exists for the same reason `LocalHTTPConnectProxy` does -- no pre-existing NIO-backend fixture
/// proves a proxied connection actually carries traffic, only that `Internals.Proxy`'s config
/// mapping is shaped correctly. Accepts the greeting (`VER NMETHODS METHODS`), replies with
/// no-authentication (`0x00`) if offered, accepts one `CONNECT` request (`VER CMD RSV ATYP
/// DST.ADDR DST.PORT`), replies success, then relays raw bytes both ways between the accepted
/// connection and a freshly dialed one to the requested address -- opaque after that point,
/// exactly like `LocalHTTPConnectProxy`'s own tunnel (`OutboundRelayHandler`, shared verbatim).
///
/// The exact bytes this responds to were captured empirically, not assumed from RFC 1928 alone:
/// `URLSession`, given only `SOCKSEnable`/`SOCKSProxy`/`SOCKSPort` (no `SOCKSVersion`), sends a
/// SOCKS5 greeting offering no-authentication (`05 01 00`) and, for a domain-name destination, a
/// `CONNECT` request with `ATYP=0x03` (`05 01 00 03 <len> <domain> <port>`) -- confirmed by
/// capturing the raw bytes a bare listener received, not by reading CFNetwork source or docs
/// (there is no public documentation of this default at all).
struct LocalSOCKSProxy: Sendable {

    // MARK: - Internal properties

    let host = "127.0.0.1"
    let port: Int

    /// How many complete `CONNECT` requests this proxy has actually parsed, successful or not --
    /// same purpose as `LocalHTTPConnectProxy.connectAttempts`.
    let connectAttempts: ConnectAttemptCounter

    // MARK: - Private properties

    private let group: EventLoopGroup
    private let channel: Channel

    // MARK: - Internal static methods

    static func start() async throws -> LocalSOCKSProxy {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let connectAttempts = ConnectAttemptCounter()

        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(SOCKSHandler(group: group, connectAttempts: connectAttempts))
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()

        guard let port = channel.localAddress?.port else {
            struct MissingLocalPortError: Error {}
            throw MissingLocalPortError()
        }

        return LocalSOCKSProxy(port: port, connectAttempts: connectAttempts, group: group, channel: channel)
    }

    // MARK: - Internal methods

    func shutdown() async throws {
        try await channel.close()
        try await group.shutdownGracefully()
    }
}

/// One instance per accepted connection. Walks `.awaitingGreeting` -> `.awaitingRequest` ->
/// `.relaying(Channel)` in order, hand-parsing the binary SOCKS5 framing incrementally (unlike
/// `LocalHTTPConnectProxy`'s line-oriented HTTP text, there is no delimiter to scan for -- each
/// message's own length fields say how many more bytes are needed).
///
/// `@unchecked` rather than provably `Sendable`: NIO guarantees every `ChannelHandler` callback
/// for one channel runs on that channel's own `EventLoop`, one at a time, so `mode`/`buffer` are
/// never actually touched concurrently. `startRelay(...)`'s `[weak self]` capture (needed since
/// `ClientBootstrap(...).connect(...)`'s completion isn't guaranteed to land back on that same
/// `EventLoop`) is itself what actually needs this -- the write to `mode` inside it is explicitly
/// hopped onto `clientChannel.eventLoop` (this handler's own) before touching it.
private final class SOCKSHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum Mode {
        case awaitingGreeting
        case awaitingRequest
        case relaying(Channel)
    }

    // MARK: - Private properties

    private let group: EventLoopGroup
    private let connectAttempts: ConnectAttemptCounter

    // MARK: - Unsafe properties

    private var mode: Mode = .awaitingGreeting
    private var buffer: ByteBuffer = ByteBufferAllocator().buffer(capacity: 512)

    // MARK: - Inits

    init(group: EventLoopGroup, connectAttempts: ConnectAttemptCounter) {
        self.group = group
        self.connectAttempts = connectAttempts
    }

    // MARK: - Internal methods

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)

        switch mode {
        case .relaying(let destination):
            destination.writeAndFlush(incoming, promise: nil)

        case .awaitingGreeting, .awaitingRequest:
            buffer.writeBuffer(&incoming)
            processBuffer(context: context)
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

    private func processBuffer(context: ChannelHandlerContext) {
        switch mode {
        case .awaitingGreeting:
            processGreeting(context: context)
        case .awaitingRequest:
            processRequest(context: context)
        case .relaying:
            break
        }
    }

    /// `VER(1)=0x05 NMETHODS(1) METHODS(NMETHODS)`. Refuses (`05 FF`, then closes) if
    /// no-authentication (`0x00`) isn't among the offered methods -- this proxy supports nothing
    /// else, matching the NIO backend's own `.socksServer(host:port:)`, which takes no credentials
    /// either.
    private func processGreeting(context: ChannelHandlerContext) {
        guard
            let version = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self),
            let methodCount = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self)
        else {
            return
        }

        let messageLength = 2 + Int(methodCount)
        guard buffer.readableBytes >= messageLength else { return }

        guard
            version == 0x05,
            let methods = buffer.getBytes(at: buffer.readerIndex + 2, length: Int(methodCount)),
            methods.contains(0x00)
        else {
            reply(channel: context.channel, bytes: [0x05, 0xFF], thenClose: true)
            return
        }

        buffer.moveReaderIndex(forwardBy: messageLength)
        reply(channel: context.channel, bytes: [0x05, 0x00], thenClose: false)

        mode = .awaitingRequest
        processBuffer(context: context)
    }

    /// `VER(1)=0x05 CMD(1) RSV(1) ATYP(1) DST.ADDR(variable) DST.PORT(2)`. Only `CMD=0x01`
    /// (`CONNECT`) is supported -- `BIND`/`UDP ASSOCIATE` reply `command not supported` (`0x07`).
    /// `ATYP` `0x01` (IPv4), `0x03` (domain name, length-prefixed), and `0x04` (IPv6) are all
    /// parsed; anything else replies `address type not supported` (`0x08`).
    private func processRequest(context: ChannelHandlerContext) {
        let base = buffer.readerIndex
        guard buffer.readableBytes >= 4 else { return }

        guard
            let version = buffer.getInteger(at: base, as: UInt8.self),
            let command = buffer.getInteger(at: base + 1, as: UInt8.self),
            let addressType = buffer.getInteger(at: base + 3, as: UInt8.self)
        else {
            return
        }

        let addressStart: Int
        let addressLength: Int

        switch addressType {
        case 0x01:
            addressStart = base + 4
            addressLength = 4
        case 0x04:
            addressStart = base + 4
            addressLength = 16
        case 0x03:
            guard let domainLength = buffer.getInteger(at: base + 4, as: UInt8.self) else { return }
            addressStart = base + 5
            addressLength = Int(domainLength)
        default:
            failRequest(channel: context.channel, reply: 0x08)
            return
        }

        let portStart = addressStart + addressLength
        let messageLength = (portStart + 2) - base

        guard buffer.readableBytes >= messageLength else { return }

        guard version == 0x05 else {
            context.close(promise: nil)
            return
        }

        guard
            command == 0x01,
            let addressBytes = buffer.getBytes(at: addressStart, length: addressLength),
            let portHighByte = buffer.getInteger(at: portStart, as: UInt8.self),
            let portLowByte = buffer.getInteger(at: portStart + 1, as: UInt8.self)
        else {
            failRequest(channel: context.channel, reply: 0x07)
            return
        }

        let destinationHost = Self.host(fromAddressType: addressType, bytes: addressBytes)
        let destinationPort = Int(portHighByte) << 8 | Int(portLowByte)

        connectAttempts.increment()

        buffer.moveReaderIndex(forwardBy: messageLength)
        let leftover = buffer.readableBytes > 0 ? buffer.readSlice(length: buffer.readableBytes) : nil
        buffer.clear()

        startRelay(host: destinationHost, port: destinationPort, leftover: leftover, channel: context.channel)
    }

    private func failRequest(channel: Channel, reply replyCode: UInt8) {
        reply(channel: channel, bytes: [0x05, replyCode, 0x00, 0x01, 0, 0, 0, 0, 0, 0], thenClose: true)
    }

    // Raw `ByteBuffer`, not `wrapOutboundOut(out)`'s `NIOAny` -- `Channel.writeAndFlush` has a
    // generic `Sendable`-constrained overload for exactly this (`ByteBuffer` is `Sendable`), where
    // the `NIOAny`-typed overload is deprecated. Takes `channel` rather than `context` throughout
    // this handler's private helpers -- `Channel`, unlike `ChannelHandlerContext`, is `Sendable`,
    // so it's safe to pass into `startRelay(...)`'s `[weak self]` completion, which isn't
    // guaranteed to already be running on this handler's own `EventLoop`.
    private func reply(channel: Channel, bytes: [UInt8], thenClose: Bool) {
        var out = channel.allocator.buffer(capacity: bytes.count)
        out.writeBytes(bytes)

        channel.writeAndFlush(out).whenComplete { _ in
            if thenClose {
                channel.close(promise: nil)
            }
        }
    }

    /// Dials `host:port`, answers the request with success (`05 00`), and flips `mode` to
    /// `.relaying` -- from here on `channelRead` forwards to `outboundChannel` directly. Mirrors
    /// `LocalHTTPConnectProxy`'s own `startRelay(host:port:leftover:context:)` structurally (that
    /// one keeps `context` -- it never needs to call a `context`-taking helper from inside the
    /// `[weak self]` completion the way `failRequest`/`reply` here do, so it never hits the same
    /// non-`Sendable`-capture warning `channel` fixes here); the
    /// bound address/port in the success reply are zeroed (`0.0.0.0:0`), which real SOCKS clients
    /// -- `URLSession` included, confirmed by this file's own round-trip tests actually passing --
    /// don't require to be meaningful.
    private func startRelay(host: String, port: Int, leftover: ByteBuffer?, channel clientChannel: Channel) {
        ClientBootstrap(group: group).connect(host: host, port: port).whenComplete { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure:
                self.failRequest(channel: clientChannel, reply: 0x05)

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

                            self.reply(
                                channel: clientChannel,
                                bytes: [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0],
                                thenClose: false
                            )

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

    private static func host(fromAddressType addressType: UInt8, bytes: [UInt8]) -> String {
        switch addressType {
        case 0x01:
            return bytes.map { String($0) }.joined(separator: ".")
        case 0x04:
            // No `Foundation`/`String(format:)` dependency needed for this rarely-hit branch --
            // every test destination this proxy actually sees is a domain name (`0x03`).
            return stride(from: 0, to: bytes.count, by: 2)
                .map { index -> String in
                    let group = (UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1])
                    let hex = String(group, radix: 16)
                    return String(repeating: "0", count: 4 - hex.count) + hex
                }
                .joined(separator: ":")
        default:  // 0x03 -- domain name
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
