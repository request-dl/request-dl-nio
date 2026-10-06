//
// See LICENSE for this package's licensing information.
//

import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

/// Unit coverage for `Internals.FlowControlWindow`'s suspension and for
/// `Internals.TransferControl`, which applies it to every window of an execution. The end-to-end
/// behaviour -- on real connections, both executors -- is in
/// `InternalsTransferControlDownloadTests`/`InternalsTransferControlUploadTests`.
struct InternalsTransferControlTests {

    // MARK: - Window suspension

    @Test
    func suspend_shutsAWindowWithNothingBuffered() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let resumed = LockedValueBox(0)

        // When
        window.suspend()
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }

        // Then
        #expect(!window.isWritable)
        #expect(window.isSuspended)
        #expect(resumed.withLockedValue { $0 } == 0)
        #expect(window.waitingCountForTesting == 1)

        window.resume()
        #expect(window.isWritable)
        #expect(resumed.withLockedValue { $0 } == 1)
    }

    /// The reader draining the backlog -- even all of it -- must not wake a suspended producer:
    /// only `resume()` (or `release()`) may.
    @Test
    func credit_whileSuspended_neverWakesTheProducer() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let resumed = LockedValueBox(0)

        window.charge(150)
        window.suspend()
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }

        // When
        window.credit(150)

        // Then
        #expect(resumed.withLockedValue { $0 } == 0)
        #expect(!window.isWritable)

        window.resume()
        #expect(resumed.withLockedValue { $0 } == 1)
    }

    /// Resuming only lifts the suspension: a backlog still past the high watermark keeps the
    /// producer waiting for the reader, exactly as if it had never been suspended.
    @Test
    func resume_withTheBacklogStillAboveTheHighWatermark_waitsForTheLowWatermark() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let resumed = LockedValueBox(0)

        window.charge(150)
        window.suspend()
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }

        // When
        window.resume()

        // Then
        #expect(resumed.withLockedValue { $0 } == 0)

        window.credit(60)  // 90
        #expect(resumed.withLockedValue { $0 } == 0)

        window.credit(40)  // 50
        #expect(resumed.withLockedValue { $0 } == 1)
    }

    /// A producer that was only waiting for the suspension, with a backlog between the two
    /// watermarks, goes on as soon as it's lifted: it would never have stopped otherwise.
    @Test
    func resume_withTheBacklogBetweenTheWatermarks_letsTheProducerGoAtOnce() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let resumed = LockedValueBox(0)

        window.charge(80)
        window.suspend()
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }

        // When
        window.resume()

        // Then
        #expect(resumed.withLockedValue { $0 } == 1)
    }

    /// The liveness guarantee a suspension leans on: whatever ends the exchange releases the
    /// window, and a release frees a suspended producer like it frees a paused one, for good.
    @Test
    func release_overridesASuspension() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let resumed = LockedValueBox(0)

        window.suspend()
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }

        // When
        window.release()

        // Then
        #expect(resumed.withLockedValue { $0 } == 1)
        #expect(window.isWritable)

        // Suspending a released window holds nothing back.
        window.suspend()
        #expect(window.isWritable)
    }

    @Test
    func suspendAndResume_areIdempotent() {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 100, lowWatermark: 50)
        let resumed = LockedValueBox(0)

        // When
        window.suspend()
        window.suspend()
        window.whenWritable { resumed.withLockedValue { $0 += 1 } }
        window.resume()
        window.resume()

        // Then
        #expect(resumed.withLockedValue { $0 } == 1)
        #expect(!window.isSuspended)
    }

    @Test
    func waitUntilWritable_whileSuspended_returnsOnResume() async throws {
        // Given
        let window = Internals.FlowControlWindow()
        window.suspend()

        let waiter = Task {
            await window.waitUntilWritable()
        }

        try await eventually { window.waitingCountForTesting == 1 }

        // When
        window.resume()

        // Then
        try await completing(within: 5) {
            await waiter.value
        }
    }

    // MARK: - TransferControl

    @Test
    func transferControl_suspendsTheGateAndEveryAttachedWindow() {
        // Given
        let control = Internals.TransferControl()
        let first = Internals.FlowControlWindow()
        let second = Internals.FlowControlWindow()

        control.attach(first)
        control.attach(second)

        // When
        control.suspend()

        // Then
        #expect(control.isSuspended)
        #expect(!control.gate.isWritable)
        #expect(!first.isWritable)
        #expect(!second.isWritable)

        control.resume()
        #expect(!control.isSuspended)
        #expect(control.gate.isWritable)
        #expect(first.isWritable)
        #expect(second.isWritable)
    }

    /// A suspension that comes before the executor attaches its window -- the app pausing a
    /// request that hasn't reached the network yet -- still holds once it does.
    @Test
    func transferControl_attachingAfterASuspension_startsSuspended() {
        // Given
        let control = Internals.TransferControl()
        control.suspend()

        // When
        let window = Internals.FlowControlWindow()
        control.attach(window)

        // Then
        #expect(!window.isWritable)

        control.resume()
        #expect(window.isWritable)
    }

    /// Releasing the control opens its gate for good (freeing an upload or a reconnection parked
    /// on it), and leaves the attached windows to their own terminal paths.
    // MARK: - Followers

    @Test
    func transferControl_aFollower_suspendsAndResumesWithTheControlItFollows() {
        // Given
        let parent = Internals.TransferControl()
        let follower = Internals.TransferControl()
        let window = Internals.FlowControlWindow()

        follower.attach(window)
        parent.attach(follower)

        // When
        parent.suspend()

        // Then: everything the follower holds is held, including what its executor attached.
        #expect(follower.isSuspended)
        #expect(!follower.gate.isWritable)
        #expect(window.isSuspended)

        parent.resume()
        #expect(!follower.isSuspended)
        #expect(follower.gate.isWritable)
        #expect(!window.isSuspended)
    }

    @Test
    func transferControl_aFollowerAttachedWhileSuspended_startsSuspended() {
        // Given
        let parent = Internals.TransferControl()
        let follower = Internals.TransferControl()

        parent.suspend()

        // When
        parent.attach(follower)

        // Then
        #expect(follower.isSuspended)
    }

    @Test
    func transferControl_aFollowerThatEnded_isNoLongerAffected() {
        // Given
        let parent = Internals.TransferControl()
        let follower = Internals.TransferControl()
        parent.attach(follower)

        // When
        parent.detach(follower)
        parent.suspend()

        // Then
        #expect(parent.isSuspended)
        #expect(!follower.isSuspended)
    }

    /// The reason a follower exists at all: the executor of one exchange releases the control it
    /// is given when that exchange ends, and that must not free what the execution holds.
    @Test
    func transferControl_releasingAFollower_leavesTheControlItFollowsHeld() {
        // Given
        let parent = Internals.TransferControl()
        let follower = Internals.TransferControl()
        parent.attach(follower)
        parent.suspend()

        // When
        follower.release()

        // Then
        #expect(follower.gate.isWritable)
        #expect(!parent.gate.isWritable)
        #expect(parent.isSuspended)
    }

    @Test
    func transferControl_release_opensTheGateForGood() async throws {
        // Given
        let control = Internals.TransferControl()
        control.suspend()

        let waiter = Task {
            await control.waitUntilResumed()
        }

        try await eventually { control.gate.waitingCountForTesting == 1 }

        // When
        control.release()

        // Then
        try await completing(within: 5) {
            await waiter.value
        }

        #expect(control.gate.isReleasedForTesting)
        control.suspend()
        #expect(control.gate.isWritable)
    }

    /// Suspending and resuming from many tasks at once, as an app's UI and its background work
    /// could, always leaves every participant agreeing with whichever call ran last.
    @Test
    func transferControl_concurrentSuspendAndResume_neverLeavesTheWindowsDisagreeing() async {
        for _ in 0..<50 {
            // Given
            let control = Internals.TransferControl()
            let windows = (0..<4).map { _ in Internals.FlowControlWindow() }
            windows.forEach(control.attach)

            // When
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<64 {
                    group.addTask {
                        if index.isMultiple(of: 2) {
                            control.suspend()
                        } else {
                            control.resume()
                        }
                    }
                }
            }

            // Then
            let isSuspended = control.isSuspended
            #expect(control.gate.isSuspended == isSuspended)
            #expect(windows.allSatisfy { $0.isSuspended == isSuspended })
        }
    }
}
