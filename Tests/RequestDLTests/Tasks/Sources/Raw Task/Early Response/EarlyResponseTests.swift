//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A server that answers a request, and goes away, before the body is all sent: `413 Content Too
/// Large`, `408 Request Timeout`, `401` for a body that was not worth sending, and so on.
///
/// The AsyncHTTPClient this package builds on used to hang on such an exchange, or report the
/// closed connection and lose the answer. The fork this package requires (1.42.0) hands the answer
/// over instead. Nothing in this repository exercised that, so an update of the fork, of
/// AsyncHTTPClient or a change of the receivers could have brought the hang back unnoticed. These
/// tests are what notices, on every platform `.nio` runs on: the real exchange, over a real
/// socket, with a body streaming for as long as the server lets it.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct EarlyResponseTests {

    // MARK: - Private types

    struct Case: Sendable, CustomTestStringConvertible {
        let executor: TransferTestExecutor
        let status: Int
        let keepAlive: Bool

        var testDescription: String {
            "\(executor.testDescription), \(status), \(keepAlive ? "keeps the connection" : "closes the connection")"
        }
    }

    /// Every executor built on AsyncHTTPClient that this build has.
    static let executors = TransferTestExecutor.allCases.filter(\.isNIO)

    private struct TimedOut: Error {}

    /// More than any socket buffer holds, so the body is still being written when the answer
    /// arrives, however large the buffers of the machine are.
    private static let bodySize = 16 * 1_024 * 1_024

    static let cases: [Case] = executors.flatMap { executor in
        [200, 204, 401, 408, 413, 429, 503].flatMap { status in
            [false, true].map { Case(executor: executor, status: status, keepAlive: $0) }
        }
    }

    // MARK: - Tests

    @Test(.timeLimit(.minutes(2)), arguments: cases)
    func aPostWhoseBodyIsStillStreaming_getsTheAnswerTheServerGaveBeforeItEnded(_ scenario: Case) async throws {
        // Given
        let server = try await EarlyResponseServer(status: scenario.status, keepAlive: scenario.keepAlive)

        // When
        let result: TaskResult<Data>

        do {
            result = try await Self.post(to: server, over: scenario.executor)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()

        // Then
        #expect(result.head.status.code == scenario.status)
    }

    /// The answer is not an accident of one lucky exchange: the same client, over and over, never
    /// loses one and never hangs. Every request here is on a connection of its own, the server
    /// being closed each time.
    @Test(.timeLimit(.minutes(2)), arguments: executors)
    func manyExchangesInARow_neverHangAndNeverLoseTheAnswer(_ executor: TransferTestExecutor) async throws {
        for index in 0..<20 {
            let status = [408, 413, 429, 503, 200][index % 5]
            let server = try await EarlyResponseServer(status: status)

            do {
                let result = try await Self.post(to: server, over: executor)
                #expect(result.head.status.code == status)
            } catch {
                await server.stop()
                throw error
            }

            await server.stop()
        }
    }

    // MARK: - Private methods

    /// The POST, with a limit of time of its own: a hang is a failure that says so, instead of a
    /// suite that never ends.
    private static func post(
        to server: EarlyResponseServer,
        over executor: TransferTestExecutor
    ) async throws -> TaskResult<Data> {
        try await withThrowingTaskGroup(of: TaskResult<Data>.self) { group in
            group.addTask {
                try await UploadTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/upload")
                    RequestMethod(.post)

                    executor.pinnedSession

                    Payload(data: Data(repeating: 0x2A, count: bodySize))
                }
                .collectData()
                .result()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                throw TimedOut()
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw TimedOut()
            }

            return result
        }
    }
}

#endif
