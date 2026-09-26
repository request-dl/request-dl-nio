//
// See LICENSE for this package's licensing information.
//

import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsFlowControlWindowTests {

    @Test
    func whenWritable_whileAtOrBelowHighWatermark_runsImmediately() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let didRun = LockedValueBox(false)

        // When
        window.charge(100)
        window.whenWritable { didRun.withLockedValue { $0 = true } }

        // Then
        #expect(window.isWritable)
        #expect(didRun.withLockedValue { $0 })
        #expect(window.waitingCountForTesting == 0)
    }

    /// The hysteresis: a producer paused above the high watermark is not resumed the moment the
    /// backlog dips back under it, only once readers bring it down to the low one. Resuming at
    /// the high watermark would flip the producer back and forth once per chunk.
    @Test
    func whenWritable_aboveHighWatermark_resumesOnlyAtLowWatermark() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let resumed = LockedValueBox(0)

        window.charge(150)
        #expect(!window.isWritable)

        // When
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }

        // Then
        #expect(resumed.withLockedValue { $0 } == 0)
        #expect(window.waitingCountForTesting == 1)

        window.credit(60)  // 90: back under the high watermark, still above the low one
        #expect(resumed.withLockedValue { $0 } == 0)

        window.credit(40)  // 50: at the low watermark
        #expect(resumed.withLockedValue { $0 } == 1)
        #expect(window.waitingCountForTesting == 0)

        // Exactly once, however much more gets credited afterwards.
        window.credit(50)
        #expect(resumed.withLockedValue { $0 } == 1)
    }

    @Test
    func release_resumesEveryWaiterAndNeverPausesAgain() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let resumed = LockedValueBox(0)

        window.charge(1_000)
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }

        // When
        window.release()

        // Then
        #expect(resumed.withLockedValue { $0 } == 2)
        #expect(window.isWritable)

        // Terminal: charging far past the high watermark afterwards pauses nothing.
        window.charge(1_000_000)
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }

        #expect(window.isWritable)
        #expect(resumed.withLockedValue { $0 } == 3)
        #expect(window.waitingCountForTesting == 0)
    }

    /// The safety net that keeps a NIO producer's `EventLoopPromise` from being dropped
    /// unfulfilled if a window ever goes away with it still registered.
    @Test
    func deinit_resumesWaitersLeftBehind() {
        // Given
        let resumed = LockedValueBox(false)

        do {
            let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
            window.charge(1_000)
            window.whenWritable { resumed.withLockedValue { $0 = true } }

            #expect(!resumed.withLockedValue { $0 })
        }

        // Then
        #expect(resumed.withLockedValue { $0 })
    }

    @Test
    func waitUntilWritable_suspendsUntilCredited() async throws {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let finished = LockedValueBox(false)

        window.charge(200)

        let waiter = _Concurrency.Task {
            await window.waitUntilWritable()
            finished.withLockedValue { $0 = true }
        }

        // When
        try await eventually { window.waitingCountForTesting == 1 }
        #expect(!finished.withLockedValue { $0 })

        window.credit(150)

        // Then
        await waiter.value
        #expect(finished.withLockedValue { $0 })
    }

    @Test
    func peakBufferedBytes_tracksTheHighestBacklog() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)

        // When
        window.charge(70)
        window.charge(40)
        window.credit(100)
        window.charge(20)

        // Then
        #expect(window.bufferedBytesForTesting == 30)
        #expect(window.peakBufferedBytesForTesting == 110)
    }
}
