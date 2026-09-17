//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import NIOCore
import NIOPosix

/// A bare TCP server that accepts a connection and never writes anything back, used to keep a
/// request genuinely in flight so it can be cancelled mid-request, something `LocalServer`
/// cannot do, since it always answers immediately.
func withHangingServer<Result>(
    _ body: (Int) async throws -> Result
) async throws -> Result {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let bootstrap = ServerBootstrap(group: group)
        .childChannelInitializer { channel in
            channel.pipeline.addHandler(HangingServerHandler())
        }

    let serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
    let port = serverChannel.localAddress!.port!

    do {
        let result = try await body(port)
        try? await serverChannel.close()
        try await group.shutdownGracefully()
        return result
    } catch {
        try? await serverChannel.close()
        try await group.shutdownGracefully()
        throw error
    }
}

private final class HangingServerHandler: ChannelInboundHandler, @unchecked Sendable {

    typealias InboundIn = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Deliberately does nothing: the client is left waiting for a response that never
        // comes, until the test cancels it.
    }
}

#else

import Network
import SwiftAsyncStream

/// Network.framework counterpart to the NIO-backed `withHangingServer` above: same contract
/// (accept a connection, never write back), so `InternalsURLSessionClientTests`' cancellation
/// test runs identically regardless of which backend is actually behind it.
func withHangingServer<Result>(
    _ body: (Int) async throws -> Result
) async throws -> Result {
    let queue = DispatchQueue(label: "com.requestdl.tests.hanging-server")
    let listener = try NWListener(using: .tcp, on: .any)

    // Accepted, then deliberately left untouched: no `receive`, no `send`. The client is left
    // waiting for a response that never comes, until the test cancels it.
    listener.newConnectionHandler = { connection in
        connection.start(queue: queue)
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
        let box = HangingServerContinuationBox(continuation)

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                box.resume(returning: ())
            case .failed(let error):
                box.resume(throwing: error)
            default:
                break
            }
        }

        listener.start(queue: queue)
    }

    guard let port = listener.port else {
        listener.cancel()
        throw HangingServerError.noPortAssigned
    }

    do {
        let result = try await body(Int(port.rawValue))
        listener.cancel()
        return result
    } catch {
        listener.cancel()
        throw error
    }
}

private enum HangingServerError: Swift.Error, Sendable {
    case noPortAssigned
}

/// Same one-shot, thread-safe continuation wrapper `LocalServer.PortableServer` already uses for
/// bridging an `NWListener`'s state handler to `async`; duplicated locally rather than shared
/// across targets, since `RequestDLTestSupport` isn't a dependency of `RequestDLInternalsTests`.
private final class HangingServerContinuationBox: @unchecked Sendable {

    private let lock = Lock()
    private var continuation: CheckedContinuation<Void, Swift.Error>?

    init(_ continuation: CheckedContinuation<Void, Swift.Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Void) {
        let continuation = take()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Swift.Error) {
        let continuation = take()
        continuation?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Swift.Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

#endif
