//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsExecutorTests {

    @Test
    func executor_whenEquals() {
        // Given
        let lhs = Internals.Executor.urlSession
        let rhs = Internals.Executor.urlSession

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func executor_whenNotEquals() {
        // Given
        let lhs = Internals.Executor.urlSession
        let rhs = Internals.Executor.nioTransportServices

        // Then
        #expect(lhs != rhs)
    }

    @Test
    func executor_whenHashable() {
        // Given
        let cases: Set<Internals.Executor> = [
            .urlSession,
            .nioTransportServices,
            .nio,
        ]

        // Then
        #expect(cases.count == 3)
    }
}
