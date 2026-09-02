//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsResourceDeadlineTests {

    @Test
    func race_whenNoDeadlineConfigured_runsOperationToCompletion() async throws {
        // Given
        let deadline = Internals.ResourceDeadline(nanoseconds: nil)

        // When
        let result = try await deadline.race {
            try await Task.sleep(nanoseconds: 50_000_000)
            return "done"
        }

        // Then
        #expect(result == "done")
    }

    @Test
    func race_whenOperationFinishesBeforeDeadline_returnsItsResult() async throws {
        // Given -- deadline generous relative to the operation.
        let deadline = Internals.ResourceDeadline(nanoseconds: 2_000_000_000)

        // When
        let result = try await deadline.race {
            try await Task.sleep(nanoseconds: 10_000_000)
            return "done"
        }

        // Then
        #expect(result == "done")
    }

    @Test
    func race_whenOperationOutlivesDeadline_throwsResourceTimeoutError() async throws {
        // Given -- deadline much shorter than the operation.
        let deadline = Internals.ResourceDeadline(nanoseconds: 10_000_000)

        // When / Then
        await #expect(throws: Internals.ResourceTimeoutError.self) {
            try await deadline.race {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "done"
            }
        }
    }

    @Test
    func race_whenOperationOutlivesDeadline_cancelsGivenSeed() async throws {
        // Given
        let deadline = Internals.ResourceDeadline(nanoseconds: 10_000_000)

        actor CancellationFlag {
            private(set) var wasCancelled = false
            func markCancelled() { wasCancelled = true }
        }

        let flag = CancellationFlag()
        let seed = Internals.TaskSeed {
            Task { await flag.markCancelled() }
        }

        // When
        _ = try? await deadline.race(seed: seed) {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return "done"
        }

        // `TaskSeed` hops onto its own `Task` synchronously from a non-async closure, so give it
        // a moment to actually mark the flag before checking.
        try await Task.sleep(nanoseconds: 50_000_000)

        // Then
        #expect(await flag.wasCancelled)
    }

    @Test
    func race_whenOperationFinishesBeforeDeadline_neverCancelsGivenSeed() async throws {
        // Given
        let deadline = Internals.ResourceDeadline(nanoseconds: 2_000_000_000)

        actor CancellationFlag {
            private(set) var wasCancelled = false
            func markCancelled() { wasCancelled = true }
        }

        let flag = CancellationFlag()
        let seed = Internals.TaskSeed {
            Task { await flag.markCancelled() }
        }

        // When
        _ = try await deadline.race(seed: seed) {
            try await Task.sleep(nanoseconds: 10_000_000)
            return "done"
        }

        // Then
        #expect(await flag.wasCancelled == false)
    }
}
