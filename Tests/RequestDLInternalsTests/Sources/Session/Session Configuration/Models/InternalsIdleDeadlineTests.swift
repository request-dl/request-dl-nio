//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// The idle deadline against a clock the test moves, so what runs out and when is exact: nothing
/// here waits for real time to pass.
struct InternalsIdleDeadlineTests {

    private static let budget: Int64 = 1_000

    // MARK: - Tests

    /// Nothing moving for the whole budget ends the request, once, and says so.
    @Test
    func aBudgetWithNoActivity_endsTheRequest() async throws {
        // Given
        let clock = FakeIdleClock()
        let seed = Probe()
        let deadline = clock.makeDeadline(nanoseconds: Self.budget)

        deadline.attach(seed.seed)
        deadline.start()

        // When
        await clock.advanceUntilDone(deadline, by: Self.budget)

        // Then
        #expect(deadline.isExpired)
        #expect(seed.cancellations == 1)
    }

    /// One nanosecond short of the budget is still within it.
    @Test
    func aBudgetNotQuiteSpent_leavesTheRequestAlone() async throws {
        // Given
        let clock = FakeIdleClock()
        let seed = Probe()
        let deadline = clock.makeDeadline(nanoseconds: Self.budget)

        deadline.attach(seed.seed)
        deadline.start()

        // When
        await clock.advance(by: Self.budget - 1)

        // Then
        #expect(!deadline.isExpired)
        #expect(seed.cancellations == 0)

        deadline.finish()
    }

    /// Every touch gives the server the whole budget again, however long the transfer has lasted.
    @Test
    func activity_startsTheBudgetOver() async throws {
        // Given
        let clock = FakeIdleClock()
        let seed = Probe()
        let deadline = clock.makeDeadline(nanoseconds: Self.budget)

        deadline.attach(seed.seed)
        deadline.start()

        // When: far more time than the budget in all, never as much as the budget without a byte.
        for _ in 0..<5 {
            await clock.advance(by: Self.budget - 1)
            deadline.touch()
        }

        // Then
        #expect(!deadline.isExpired)
        #expect(seed.cancellations == 0)

        // And once the bytes stop, the budget runs out as usual.
        await clock.advanceUntilDone(deadline, by: Self.budget)
        #expect(deadline.isExpired)
        #expect(seed.cancellations == 1)
    }

    /// Time the client spent holding the exchange back is nobody's silence.
    @Test
    func timeTheClientHeldTheExchangeBack_doesNotCount() async throws {
        // Given
        let clock = FakeIdleClock()
        let seed = Probe()
        let deadline = clock.makeDeadline(nanoseconds: Self.budget)
        let isHeld = LockedValueBox(true)

        deadline.hold { isHeld.withLockedValue { $0 } }
        deadline.attach(seed.seed)
        deadline.start()

        // When: held for several budgets.
        for _ in 0..<4 {
            await clock.advance(by: Self.budget)
        }

        // Then
        #expect(!deadline.isExpired)

        // When: let go, and the server then stays silent for the whole budget.
        isHeld.withLockedValue { $0 = false }
        deadline.touch()

        await clock.advanceUntilDone(deadline, by: Self.budget)

        // Then
        #expect(deadline.isExpired)
        #expect(seed.cancellations == 1)
    }

    /// An exchange that ended has nothing left to time.
    @Test
    func afterTheExchangeEnds_nothingExpires() async throws {
        // Given
        let clock = FakeIdleClock()
        let seed = Probe()
        let deadline = clock.makeDeadline(nanoseconds: Self.budget)

        deadline.attach(seed.seed)
        deadline.start()
        let watcher = try #require(deadline.watcher)

        // When
        deadline.finish()
        await watcher.value
        clock.now.withLockedValue { $0 += 10 * UInt64(Self.budget) }
        deadline.touch()

        // Then
        #expect(!deadline.isExpired)
        #expect(seed.cancellations == 0)
    }

    /// A budget that ran out before the request existed ends it as soon as it does.
    @Test
    func aSeedAttachedAfterTheBudgetRanOut_isEndedAtOnce() async throws {
        // Given
        let clock = FakeIdleClock()
        let seed = Probe()
        let deadline = clock.makeDeadline(nanoseconds: Self.budget)
        deadline.start()

        // When
        await clock.advanceUntilDone(deadline, by: Self.budget)
        #expect(deadline.isExpired)
        deadline.attach(seed.seed)

        // Then
        #expect(seed.cancellations == 1)
    }

    /// A request that went away on its own (its `TaskSeed` released, which cancels it) is not
    /// kept alive by a timer, and is not reported as having gone idle.
    @Test
    func aRequestThatIsGone_isLeftAlone() async throws {
        // Given
        let clock = FakeIdleClock()
        let deadline = clock.makeDeadline(nanoseconds: Self.budget)
        var probe: Probe? = Probe()

        deadline.attach(try #require(probe).seed)
        deadline.start()
        let watcher = try #require(deadline.watcher)

        // When: the request goes away once the watcher is counting.
        await clock.waitForASleeper()
        probe = nil
        await clock.advanceUntilDone(deadline, by: Self.budget)
        await watcher.value

        // Then
        #expect(!deadline.isExpired)
    }

    /// One watcher per deadline, and none once it has ended.
    @Test
    func start_whenCalledAgainOrAfterTheEnd_startsNothingNew() async throws {
        // Given
        let clock = FakeIdleClock()
        let deadline = clock.makeDeadline(nanoseconds: Self.budget)

        // When
        deadline.start()
        let watcher = try #require(deadline.watcher)
        deadline.start()

        // Then
        #expect(deadline.watcher == watcher)

        // When
        deadline.finish()
        await watcher.value
        deadline.start()

        // Then
        #expect(deadline.watcher == watcher)
    }

    /// "Never" is no deadline at all, and anything under it is one.
    @Test
    func aBudgetOfNever_hasNoDeadline() {
        #expect(Internals.IdleDeadline.make(nanoseconds: .max) == nil)
        #expect(Internals.IdleDeadline.make(nanoseconds: .max - 1) != nil)
        #expect(Internals.IdleDeadline.make(nanoseconds: 60_000_000_000) != nil)
    }

    // MARK: - What feeds it

    /// What every executor reports to its observer is what keeps a request alive, whether or not
    /// anything is watching the observer itself.
    @Test
    func theObserver_countsEveryByteAndHeadAndResumptionAsActivity() async throws {
        // Given
        let clock = FakeIdleClock()
        let seed = Probe()
        let deadline = clock.makeDeadline(nanoseconds: Self.budget)
        let observer = Internals.ExecutionObserver(idle: deadline)

        deadline.attach(seed.seed)
        deadline.start()

        let head = Internals.ResponseHead(
            url: "http://localhost/",
            status: .init(code: 200, reason: ""),
            version: .init(minor: 1, major: 1),
            headers: [],
            isKeepAlive: true
        )

        let signals: [@Sendable () -> Void] = [
            { observer.didSend(1) },
            { observer.didReceive(1) },
            { observer.didReceiveHead(head) },
            { observer.didChange(.resumed) },
            { observer.didChange(.reconnecting(attempt: 1)) },
        ]

        // When: each one, just short of the budget after the last.
        for signal in signals {
            await clock.advance(by: Self.budget - 1)
            signal()
        }

        // Then
        #expect(!deadline.isExpired)

        // And an observer that ends the execution ends the deadline with it.
        let watcher = try #require(deadline.watcher)
        observer.didChange(.finished)
        await watcher.value

        clock.now.withLockedValue { $0 += 10 * UInt64(Self.budget) }
        #expect(!deadline.isExpired)
    }

    /// Nothing counted is nothing recorded: an observer that only feeds a deadline keeps no
    /// progress for anyone, and so has no backlog to grow.
    @Test
    func anObserverWithoutADelivery_recordsNothing() async throws {
        // Given
        let observer = Internals.ExecutionObserver(idle: nil)

        // When
        observer.didSend(10)
        observer.didReceive(10)
        observer.didChange(.started)
        observer.didChange(.finished)

        // Then: nothing to crash on, and nothing to wait for.
        observer.didChange(.failed(AnyError()))
    }
}

// MARK: - Helpers

/// Counts how many times a request was ended.
private final class Probe: @unchecked Sendable {

    private let count = LockedValueBox(0)

    var cancellations: Int {
        count.withLockedValue { $0 }
    }

    private(set) var seed: Internals.TaskSeed!

    init() {
        seed = Internals.TaskSeed { [count] in
            count.withLockedValue { $0 += 1 }
        }
    }
}
