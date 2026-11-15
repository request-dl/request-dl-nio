//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

struct IdleBoundedClientTests {

    private struct Refused: Error {}

    /// Never answers the conditional request.
    private struct SilentClient: RequestExecutingClient {

        func execute(
            configuration: RequestConfiguration,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            transferControl: Internals.TransferControl?
        ) async throws -> SessionTask {
            throw Refused()
        }

        func revalidationHead(
            configuration: RequestConfiguration,
            logger: Internals.TaskLogger?,
            metrics: Internals.RequestMetricsCollector?
        ) async throws -> Internals.ResponseHead {
            try await _Concurrency.Task.sleep(nanoseconds: 120_000_000_000)
            throw CancellationError()
        }
    }

    /// The conditional request is what the deadline cancels once the budget is spent on it.
    @Test
    func theConditionalRequest_isCancelledWhenTheBudgetIsSpent() async throws {
        // Given
        let clock = FakeIdleClock()
        let deadline = clock.makeDeadline(nanoseconds: 1_000)
        let client = IdleBoundedClient(SilentClient(), idle: deadline)
        deadline.start()

        // When
        let outcome = _Concurrency.Task {
            try await client.revalidationHead(configuration: RequestConfiguration(), logger: nil, metrics: nil)
        }

        await clock.advanceUntilDone(deadline, by: 1_000)

        // Then
        await #expect(throws: CancellationError.self) { try await outcome.value }
        #expect(deadline.isExpired)
    }

    /// What is not the conditional request is the client's own, and is not bounded.
    @Test
    func everythingElse_goesStraightToTheClient() async throws {
        // Given
        let clock = FakeIdleClock()
        let client = IdleBoundedClient(SilentClient(), idle: clock.makeDeadline(nanoseconds: 1_000))

        // Then
        await #expect(throws: Refused.self) {
            _ = try await client.execute(
                configuration: RequestConfiguration(),
                decompression: .disabled,
                cache: nil,
                logger: nil,
                transferControl: nil
            )
        }
    }
}
