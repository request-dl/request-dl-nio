//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

struct SessionExecutorTests {

    @Test(
        arguments: [
            (Session.Executor.urlSession, Internals.Executor.urlSession),
            (Session.Executor.nioTransportServices, Internals.Executor.nioTransportServices),
            (Session.Executor.nio, Internals.Executor.nio),
        ] as [(Session.Executor, Internals.Executor)]
    )
    func executor_whenBuilt_roundTripsThroughInternalsExecutor(
        _ pair: (Session.Executor, Internals.Executor)
    ) async throws {
        // Given
        let (executor, internalExecutor) = pair

        // Then
        #expect(executor.build() == internalExecutor)
        #expect(Session.Executor(internalExecutor) == executor)
    }

    @Test
    func executor_whenHashable() {
        // Given
        let cases: Set<Session.Executor> = [.urlSession, .nioTransportServices, .nio]

        // Then
        #expect(cases.count == 3)
    }
}
