//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOPosix
import Testing

@testable import RequestDLInternals

struct InternalsUnsafeTaskTests {

    @Test
    func response_whenCancelled_cancelsUnderlyingHTTPTask() async throws {
        try await withHangingServer { port in
            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            let client = Internals.Client(
                eventLoopGroupProvider: .shared(group),
                configuration: .init()
            )

            let request = try HTTPClient.Request(url: "http://127.0.0.1:\(port)/")
            let unsafeTask = await client.execute(request: request, logger: nil)

            let responseTask = _Concurrency.Task {
                try await unsafeTask.response()
            }

            // Gives the request a moment to actually reach the (unresponsive) server before
            // cancelling, so this exercises a genuine in-flight cancellation rather than one
            // that races the connection attempt itself.
            try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            responseTask.cancel()

            await #expect(throws: (any Error).self) {
                _ = try await responseTask.value
            }

            _ = try? await client.shutdown()
            try await group.shutdownGracefully()
        }
    }

    @Test
    func equality_comparesBySeedIdentity() async throws {
        try await withHangingServer { port in
            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            let client = Internals.Client(
                eventLoopGroupProvider: .shared(group),
                configuration: .init()
            )

            let request = try HTTPClient.Request(url: "http://127.0.0.1:\(port)/")
            let first = await client.execute(request: request, logger: nil)
            let second = await client.execute(request: request, logger: nil)
            let firstCopy = first

            // Then
            #expect(first == firstCopy)
            #expect(first.hashValue == firstCopy.hashValue)
            #expect(first != second)

            // Cleanup: both requests are still in flight against a server that never answers.
            let firstTask = _Concurrency.Task { try? await first.response() }
            let secondTask = _Concurrency.Task { try? await second.response() }
            firstTask.cancel()
            secondTask.cancel()
            _ = await firstTask.value
            _ = await secondTask.value

            _ = try? await client.shutdown()
            try await group.shutdownGracefully()
        }
    }
}

/// A bare TCP server that accepts a connection and never writes anything back — used to keep a
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

final class HangingServerHandler: ChannelInboundHandler, @unchecked Sendable {

    typealias InboundIn = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Deliberately does nothing: the client is left waiting for a response that never
        // comes, until the test cancels it.
    }
}
