//
// See LICENSE for this package's licensing information.
//

// A raw NIO listener stands in for the proxy, and `Session.requiredExecutor(.nio)` does not exist
// without NIOCore.
#if canImport(NIOCore)

import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#endif

/// What a SOCKS5 proxy that gets the credentials and then closes the connection, without sending
/// the RFC 1929 status, does to the request.
///
/// A proxy that answers with a failure status (`01 xx`) fails the request at once, and so does
/// one that closes without a status (a violation of the RFC that simple implementations and rate
/// limiters commit): the same wrong credentials are never sent again. That used to hold only for
/// the first: the fork of swift-nio-extras did nothing on the close while waiting for the
/// credentials' answer, the fork of AsyncHTTPClient reported it as `remoteConnectionClosed`, and
/// the request was retried with the same credentials until it timed out. swift-nio-extras 1.35.5
/// raises `SOCKSError.AuthenticationFailed` for that close, and async-http-client 1.42.2 treats it
/// as permanent, like a status.
struct ProxySOCKSClosedWithoutStatusTests {

    // MARK: - Private types

    /// Offers username/password authentication, takes the credentials, and then either answers
    /// with the failure status `01 01` or closes the connection without a word.
    private final class RejectingProxyHandler: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = ByteBuffer

        private let answersWithStatus: Bool
        private var reads = 0

        init(answersWithStatus: Bool) {
            self.answersWithStatus = answersWithStatus
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            reads += 1

            var reply = context.channel.allocator.buffer(capacity: 2)

            if reads == 1 {
                // Method selection: username/password.
                reply.writeBytes([0x05, 0x02])
                context.writeAndFlush(NIOAny(reply), promise: nil)
            } else if answersWithStatus {
                reply.writeBytes([0x01, 0x01])
                context.writeAndFlush(NIOAny(reply), promise: nil)
            } else {
                context.close(promise: nil)
            }
        }
    }

    private struct Outcome {
        let connections: Int
        let error: (any Error)?
    }

    // MARK: - Private methods

    /// Runs the request until it ends or `until` says enough was seen, for at most `seconds`: the
    /// tests wait for what they assert, not for a fixed time, since a loaded machine can take
    /// seconds to open a connection.
    private func run(
        answersWithStatus: Bool,
        upTo seconds: Double = 30,
        until: @Sendable (_ connections: Int) -> Bool = { _ in false }
    ) async throws -> Outcome {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let connections = NIOLockedValueBox(0)

        let server = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                connections.withLockedValue { $0 += 1 }
                return channel.pipeline.addHandler(RejectingProxyHandler(answersWithStatus: answersWithStatus))
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()

        let port = try #require(server.localAddress?.port)

        let isFinished = NIOLockedValueBox(false)

        let task = Task<(any Error)?, Never> {
            defer { isFinished.withLockedValue { $0 = true } }

            do {
                _ = try await DataTask {
                    BaseURL(.http, host: "example.invalid")
                    Session().requiredExecutor(.nio)
                    Proxy(
                        host: "127.0.0.1",
                        port: port,
                        connection: .socks,
                        authorization: .basic(username: "user", password: "WRONG")
                    )
                }
                .extractPayload()
                .result()

                return nil
            } catch {
                return error
            }
        }

        let deadline = Date().addingTimeInterval(seconds)

        // Ends as soon as the request does, or when the budget goes by.
        while Date() < deadline, !isFinished.withLockedValue({ $0 }), !until(connections.withLockedValue { $0 }) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        task.cancel()
        let error = await task.value

        try await server.close()
        try await group.shutdownGracefully()

        return Outcome(connections: connections.withLockedValue { $0 }, error: error)
    }

    // MARK: - Tests

    @Test
    func aProxyThatAnswersWithAFailureStatus_isAskedOnce() async throws {
        let outcome = try await run(answersWithStatus: true)

        #expect(outcome.connections == 1)

        let error = try #require(outcome.error)
        #expect(String(reflecting: error).contains("AuthenticationFailed"))
    }

    @Test
    func aProxyThatClosesWithoutAStatus_isAskedOnceAndReportedAsARejection() async throws {
        let outcome = try await run(answersWithStatus: false)

        // The close is taken for a rejection: one attempt, the same typed error as for a status.
        #expect(outcome.connections == 1)

        let error = try #require(outcome.error)
        let typed = try #require(error as? ProxyAuthorizationError)
        #expect(typed.reason == .socksAuthenticationRejected)
        #expect(String(reflecting: error).contains("AuthenticationFailed"))
    }
}

#endif
