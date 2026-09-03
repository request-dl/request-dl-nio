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
        // Given -- deadline generous relative to the operation. 10s rather than a merely
        // 200x-generous 2s: observed flaky on a contended CI runner (a heavily loaded shared
        // macOS runner can starve this process for well over 2 real seconds even though
        // `operation` itself only ever awaits a 10ms sleep), so this margin is sized against
        // scheduler jitter under load, not against `operation`'s own duration.
        let deadline = Internals.ResourceDeadline(nanoseconds: 10_000_000_000)

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

    /// Regression coverage for a real race, not just a hypothetical one: with `.urlSession` as
    /// the default executor on Darwin, a fast enough loopback `operation` could actually win
    /// against an already-elapsed deadline before this fast path existed -- `race(seed:_:)` used
    /// to always start `operation` and the deadline's own `Task.sleep(nanoseconds:)` (even a
    /// zero-duration one still needs a real scheduler hop) as two equally-real competing child
    /// tasks, so "already in the past" was a coin flip, not a guarantee. This deadline is built
    /// already elapsed (`nanoseconds: 0`, so even `DispatchTime.now()` right after `init` is
    /// past it), and `operation` never suspends at all -- as fast as an operation can possibly
    /// be -- so if this ever raced instead of short-circuiting, `operation` winning would be the
    /// likely outcome, not the timeout.
    @Test
    func race_whenDeadlineAlreadyElapsed_throwsWithoutRunningOperationEvenWhenOperationNeverSuspends() async throws {
        // Given
        let deadline = Internals.ResourceDeadline(nanoseconds: 0)

        actor RanFlag {
            private(set) var ran = false
            func markRan() { ran = true }
        }

        let ranFlag = RanFlag()

        // When / Then
        await #expect(throws: Internals.ResourceTimeoutError.self) {
            try await deadline.race {
                await ranFlag.markRan()
                return "done"
            }
        }

        #expect(await !ranFlag.ran)
    }

    /// Companion to the test above: an already-elapsed deadline must cancel `seed` too, the same
    /// as the outlives-deadline path already does -- `RawTask`/`AsyncResponse.Iterator` depend on
    /// that to tear down a connection this fast path now bypasses starting `operation` for.
    @Test
    func race_whenDeadlineAlreadyElapsed_cancelsGivenSeed() async throws {
        // Given
        let deadline = Internals.ResourceDeadline(nanoseconds: 0)

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
            "done"
        }

        // `TaskSeed` hops onto its own `Task` synchronously from a non-async closure, so give it
        // a moment to actually mark the flag before checking.
        try await Task.sleep(nanoseconds: 50_000_000)

        // Then
        #expect(await flag.wasCancelled)
    }

    @Test
    func race_whenOperationFinishesBeforeDeadline_neverCancelsGivenSeed() async throws {
        // Given -- see the identical note on `race_whenOperationFinishesBeforeDeadline_returnsItsResult`
        // above: 10s margin, sized against CI scheduler jitter rather than `operation`'s own 10ms.
        let deadline = Internals.ResourceDeadline(nanoseconds: 10_000_000_000)

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
