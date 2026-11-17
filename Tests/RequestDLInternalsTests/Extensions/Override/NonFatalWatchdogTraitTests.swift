//
// See LICENSE for this package's licensing information.
//

#if DEBUG
import Foundation
import Testing

@testable import RequestDLTestSupport

/// What `.nonFatalWatchdog` does with an `AsyncLock` report, and the ``PoolLagMonitor`` it asks.
///
/// The recording is injected (`NonFatalWatchdogTrait.report(_:lag:record:)`), so nothing here
/// records a real issue: an error recorded from a test would fail that test, which is the very
/// thing under test.
struct NonFatalWatchdogTraitTests {

    private static let heldLock = "🐞 RequestDL bug: AsyncLock held for more than 15.0s\nAsyncLock\n  holder: running"

    private typealias Recorded = [(message: String, severity: Issue.Severity)]

    private static func record(_ message: String, lag: PoolLagMonitor.Lag) -> Recorded {
        var recorded: Recorded = []

        NonFatalWatchdogTrait.report(message, lag: lag) {
            recorded.append(($0, $1))
        }

        return recorded
    }

    // MARK: - Reporting

    /// With nothing late, a held lock is what it always was: an error, untouched.
    @Test
    func aHeldLock_withHealthyPools_staysAnError() {
        // When
        let recorded = Self.record(Self.heldLock, lag: .none)

        // Then
        #expect(recorded.count == 1)
        #expect(recorded.first?.severity == .error)
        #expect(recorded.first?.message == Self.heldLock)
    }

    /// Lag below the threshold is not a stalled machine.
    @Test(arguments: [0.5, NonFatalWatchdogTrait.lagThreshold])
    func aHeldLock_withLagUpToTheThreshold_staysAnError(_ seconds: Double) {
        // When
        let recorded = Self.record(Self.heldLock, lag: .init(seconds: seconds, source: .filePool))

        // Then
        #expect(recorded.map(\.severity) == [.error])
        #expect(recorded.first?.message == Self.heldLock)
    }

    /// Late work turns a held lock into a warning that still carries the report and says how late.
    @Test(arguments: PoolLagMonitor.Source.allCases)
    func aHeldLock_withLagBeyondTheThreshold_becomesAWarningThatSaysWhy(_ source: PoolLagMonitor.Source) {
        // When
        let recorded = Self.record(Self.heldLock, lag: .init(seconds: 18.4, source: source))

        // Then
        #expect(recorded.count == 1)
        #expect(recorded.first?.severity == .warning)

        let message = recorded.first?.message ?? ""
        #expect(message.contains(Self.heldLock))
        #expect(message.contains(source.rawValue))
        #expect(message.contains("18s"))
    }

    /// The downgrade is for held locks only: any other report from the same hook stays an error,
    /// however late the machine is.
    @Test
    func anotherReport_withLag_staysAnError() {
        // When
        let message = "🐞 RequestDL bug: something else entirely"
        let recorded = Self.record(message, lag: .init(seconds: 60, source: .cooperativePool))

        // Then
        #expect(recorded.map(\.severity) == [.error])
        #expect(recorded.first?.message == message)
    }

    // MARK: - The monitor

    /// A probe that has not begun counts for as long as it has been waiting, so a pool stuck
    /// right now shows as late right now, then as a sample once it recovers, until it ages out.
    @Test
    func aProbeThatHasNotBegun_countsForTheTimeItHasWaited() {
        // Given
        let clock = FakeClock()
        let began = LockedValueBox<[@Sendable () -> Void]>([])
        let monitor = PoolLagMonitor(
            retention: 30,
            probes: [
                .init(source: .filePool) { work in began.withLockedValue { $0.append(work) } }
            ],
            now: { clock.now }
        )

        // When
        monitor.tick()
        clock.advance(seconds: 18)

        // Then
        #expect(monitor.worstLag(within: 20) == .init(seconds: 18, source: .filePool))

        // When
        began.withLockedValue { $0 }.first?()

        // Then: the same lag, now a recorded sample.
        #expect(monitor.worstLag(within: 20) == .init(seconds: 18, source: .filePool))

        // When
        clock.advance(seconds: 5)

        // Then
        #expect(monitor.worstLag(within: 20) == .init(seconds: 18, source: .filePool))

        // When
        clock.advance(seconds: 20)

        // Then: out of the window.
        #expect(monitor.worstLag(within: 20) == .none)
    }

    /// A probe that is still waiting is never joined by a second one, so a stuck pool is not fed
    /// more work by the thing watching it.
    @Test
    func tick_withAProbeStillPending_startsNoSecondOne() {
        // Given
        let clock = FakeClock()
        let enqueued = LockedValueBox(0)
        let monitor = PoolLagMonitor(
            probes: [
                .init(source: .cooperativePool) { _ in enqueued.withLockedValue { $0 += 1 } }
            ],
            now: { clock.now }
        )

        // When
        monitor.tick()
        clock.advance(seconds: 1)
        monitor.tick()
        monitor.tick()

        // Then
        #expect(enqueued.withLockedValue { $0 } == 1)
    }

    /// Starting twice is starting once: one thread does all the probing, and stopping ends it.
    @Test
    func start_isIdempotent_andStopEndsTheThread() async throws {
        // Given
        let threads = LockedValueBox<Set<ObjectIdentifier>>([])
        let enqueued = LockedValueBox(0)
        let monitor = PoolLagMonitor(
            interval: 0.005,
            probes: [
                .init(source: .cooperativePool) { began in
                    threads.withLockedValue { _ = $0.insert(ObjectIdentifier(Thread.current)) }
                    enqueued.withLockedValue { $0 += 1 }
                    began()
                }
            ]
        )

        // When
        monitor.start()
        monitor.start()

        try await eventually(timeout: 30) { enqueued.withLockedValue { $0 } >= 5 }
        monitor.start()
        monitor.stop()

        // Then
        #expect(threads.withLockedValue { $0.count } == 1)

        let stoppedAt = enqueued.withLockedValue { $0 }
        try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        #expect(enqueued.withLockedValue { $0 } == stoppedAt)

        // And a monitor that was stopped never starts again.
        monitor.start()
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        #expect(enqueued.withLockedValue { $0 } == stoppedAt)
    }

    /// The real probes, on the real pools: they begin, and say how long that took.
    @Test
    func theStandardProbes_measureTheRealPools() async throws {
        // Given
        let monitor = PoolLagMonitor(interval: 0.01)

        // When
        monitor.start()
        defer { monitor.stop() }

        // Then
        try await eventually(timeout: 60) { monitor.completedProbes >= 4 }
        #expect(monitor.worstLag(within: 30).seconds >= 0)
    }
}

private final class FakeClock: @unchecked Sendable {

    private let box = LockedValueBox<UInt64>(1_000_000_000)

    var now: UInt64 {
        box.withLockedValue { $0 }
    }

    func advance(seconds: Double) {
        box.withLockedValue { $0 += UInt64(seconds * 1_000_000_000) }
    }
}
#endif
