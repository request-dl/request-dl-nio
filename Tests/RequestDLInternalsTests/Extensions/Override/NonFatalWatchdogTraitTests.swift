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

    /// A held lock as the URLSession-only job reported it: `Internals.Buffer`'s file write.
    private static let heldLock = held(by: "write(at:data:) at RequestDLInternals/Internals.Buffer.swift:222")

    private static func held(by holder: String, pending: [String] = []) -> String {
        let queue = pending.isEmpty ? "  - none" : pending.map { "  - \($0)" }.joined(separator: "\n")

        return """
            🐞 RequestDL bug: AsyncLock held for more than 15.0s
            AsyncLock
            holder: running (\(holder))
            pending (\(pending.count)):
            \(queue)
            """
    }

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

    /// Lag explains a lock that waits on the file pool, not the others: the `ClientManager`
    /// resolution lock and `Client.shutdown()` carry a watchdog too, and a report from either
    /// stays an error on a runner that is stalled, since the stall says nothing about them.
    @Test(arguments: [
        "resolve(configuration:) at RequestDLInternals/Internals.ClientManager.swift:120",
        "shutdown() at RequestDLInternals/Internals.Client.swift:88",
    ])
    func aHeldLock_ofAnotherHolder_withLag_staysAnError(_ holder: String) {
        // Given
        let message = Self.held(by: holder)

        // When
        let recorded = Self.record(message, lag: .init(seconds: 18.4, source: .filePool))

        // Then
        #expect(recorded.map(\.severity) == [.error])
        #expect(recorded.first?.message == message)
    }

    /// Both operations of `Internals.Buffer` that reported in CI are file work, wherever in the
    /// file they sit now.
    @Test(arguments: [
        "write(at:data:) at RequestDLInternals/Internals.Buffer.swift:222",
        "write(at:data:) at RequestDLInternals/Internals.Buffer.swift:9999",
        "read(at:length:) at RequestDLInternals/Internals.Buffer.swift:187",
    ])
    func aHeldLock_ofTheBufferFileWork_withLag_isAWarning(_ holder: String) {
        // When
        let recorded = Self.record(Self.held(by: holder), lag: .init(seconds: 18.4, source: .filePool))

        // Then
        #expect(recorded.map(\.severity) == [.warning])
    }

    /// Only the holder counts: a Buffer call site that is merely waiting behind another holder
    /// does not make the report one of file work.
    @Test
    func aHeldLock_withTheBufferOnlyWaiting_withLag_staysAnError() {
        // Given
        let message = Self.held(
            by: "shutdown() at RequestDLInternals/Internals.Client.swift:88",
            pending: ["write(at:data:) at RequestDLInternals/Internals.Buffer.swift:222"]
        )

        // When
        let recorded = Self.record(message, lag: .init(seconds: 18.4, source: .filePool))

        // Then
        #expect(recorded.map(\.severity) == [.error])
    }

    /// A report without a holder line (or with none of ours) is not file work.
    @Test
    func isBufferFileWork_readsTheHolderLine() {
        #expect(NonFatalWatchdogTrait.isBufferFileWork(Self.heldLock))
        #expect(!NonFatalWatchdogTrait.isBufferFileWork("AsyncLock held for more than 15.0s"))
        #expect(!NonFatalWatchdogTrait.isBufferFileWork("AsyncLock\nholder: none"))
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

    /// A freeze of the whole process stops the monitor's thread too, and every probe has long
    /// begun by then, so no pool ever looks late. The thread waking late is what shows it: while
    /// it is still asleep (the gap so far counts), once it wakes (the gap is a sample), until
    /// that ages out of the window.
    @Test
    func aMonitorThreadThatStopsWaking_isLateWhileAsleep_andOnceAwake() {
        // Given
        let clock = FakeClock()
        let monitor = PoolLagMonitor(interval: 0.25, probes: [], now: { clock.now })
        monitor.heartbeat()

        // When
        clock.advance(seconds: 20.25)

        // Then
        #expect(monitor.worstLag(within: 20) == .init(seconds: 20, source: .monitorThread))

        // When
        monitor.heartbeat()

        // Then
        #expect(monitor.worstLag(within: 20) == .init(seconds: 20, source: .monitorThread))

        // When: it keeps waking on time for longer than the window.
        Self.keepWaking(monitor, clock: clock, for: 21)

        // Then
        #expect(monitor.worstLag(within: 20) == .none)
    }

    /// What the URLSession-only and iPadOS jobs saw: after a freeze, a dozen locks report at once,
    /// some before the monitor's thread wakes up from that same freeze and some after. Every one
    /// of them is a warning.
    @Test
    func severalHeldLocks_reportedAtOnceAfterAFreeze_areAllWarnings() {
        // Given
        let clock = FakeClock()
        let monitor = PoolLagMonitor(interval: 0.25, probes: Self.instantProbes, now: { clock.now })
        Self.keepWaking(monitor, clock: clock, for: 10)

        // When: everything stops for 20s, then thirteen reports and the monitor's own wake-up
        // race each other.
        clock.advance(seconds: 20)

        let recorded = LockedValueBox<Recorded>([])
        DispatchQueue.concurrentPerform(iterations: 14) { index in
            guard index != 7 else {
                monitor.heartbeat()
                monitor.tick()
                return
            }

            let lag = monitor.worstLag(within: NonFatalWatchdogTrait.lagWindow)
            let report = Self.record(Self.heldLock, lag: lag)
            recorded.withLockedValue { $0.append(contentsOf: report) }
        }

        // Then
        let all = recorded.withLockedValue { $0 }
        #expect(all.count == 13)
        #expect(all.allSatisfy { $0.severity == .warning })
        #expect(all.allSatisfy { $0.message.contains(PoolLagMonitor.Source.monitorThread.rawValue) })
    }

    /// A monitor that kept waking on time, with every probe beginning at once, is no evidence of
    /// a stall: a lock held through that is an error.
    @Test
    func aHeldLock_whileTheMonitorKeptWakingOnTime_staysAnError() {
        // Given
        let clock = FakeClock()
        let monitor = PoolLagMonitor(interval: 0.25, probes: Self.instantProbes, now: { clock.now })

        // When
        Self.keepWaking(monitor, clock: clock, for: 30)
        let recorded = Self.record(Self.heldLock, lag: monitor.worstLag(within: NonFatalWatchdogTrait.lagWindow))

        // Then
        #expect(recorded.map(\.severity) == [.error])
        #expect(recorded.first?.message == Self.heldLock)
    }

    /// What the URLSession-only job saw after the freeze theory was ruled out: the monitor's
    /// thread and the default-priority pool both on time, while `.background` work (where
    /// `DataCache` writes, holding a buffer's lock) never got a thread. That is a warning naming
    /// the starved priority, and the report shows every source's lag.
    @Test
    func aHeldLock_whileOnlyBackgroundWorkIsStarved_isAWarningThatNamesIt() {
        // Given
        let clock = FakeClock()
        let probes = PoolLagMonitor.Source.allCases.map { source in
            PoolLagMonitor.Probe(source: source) { began in
                if source != .backgroundTasks {
                    began()
                }
            }
        }
        let monitor = PoolLagMonitor(interval: 0.25, probes: probes, now: { clock.now })

        // When: its probe was handed over on the first wake-up, 15.75s before the report.
        Self.keepWaking(monitor, clock: clock, for: 16)

        let lags = monitor.lags(within: NonFatalWatchdogTrait.lagWindow)
        var recorded: Recorded = []
        NonFatalWatchdogTrait.report(Self.heldLock, lag: .worst(of: lags), lags: lags) {
            recorded.append(($0, $1))
        }

        // Then
        #expect(Set(lags.keys) == [.backgroundTasks])
        #expect(recorded.map(\.severity) == [.warning])

        let message = recorded.first?.message ?? ""
        #expect(message.contains("Lag in the last 20s: cooperative pool at background priority 15.8s"))
        #expect(message.contains("work handed to the cooperative pool at background priority started about 16s late"))
    }

    /// A held lock that stays an error still says what the monitor measured, so a report from CI
    /// shows which pools were on time.
    @Test
    func aHeldLock_thatStaysAnError_carriesEachSourcesLag() {
        // When
        var recorded: Recorded = []
        let lags: [PoolLagMonitor.Source: Double] = [.utilityTasks: 1.5, .cooperativePool: 0.5]
        NonFatalWatchdogTrait.report(Self.heldLock, lag: .worst(of: lags), lags: lags) {
            recorded.append(($0, $1))
        }

        // Then
        #expect(recorded.map(\.severity) == [.error])
        #expect(
            recorded.first?.message
                == "\(Self.heldLock)\n\nLag in the last 20s: cooperative pool 0.5s, cooperative pool at utility priority 1.5s"
        )
    }

    /// The worst lag is the one ``PoolLagMonitor/lags(within:)`` holds highest, and a tie always
    /// names the same source.
    @Test
    func worst_takesTheHighestLag_andBreaksTiesInCaseOrder() {
        #expect(PoolLagMonitor.Lag.worst(of: [:]) == .none)
        #expect(
            PoolLagMonitor.Lag.worst(of: [.fileWrite: 3, .backgroundTasks: 9, .filePool: 2])
                == .init(seconds: 9, source: .backgroundTasks)
        )
        #expect(
            PoolLagMonitor.Lag.worst(of: [.fileWrite: 7, .filePool: 7])
                == .init(seconds: 7, source: .filePool)
        )
    }

    /// A probe for every source that begins as soon as it is handed over.
    private static let instantProbes: [PoolLagMonitor.Probe] = PoolLagMonitor.Source.allCases.map { source in
        .init(source: source) { began in began() }
    }

    /// What the monitor's thread does on a healthy machine: wakes every `interval` and probes.
    private static func keepWaking(_ monitor: PoolLagMonitor, clock: FakeClock, for seconds: Double) {
        for _ in 0..<Int(seconds / 0.25) {
            clock.advance(seconds: 0.25)
            monitor.heartbeat()
            monitor.tick()
        }
    }

    /// The real probes, on the real pools: each of them begins, on its own pool.
    ///
    /// `completedProbes` alone cannot say that: the probes repeat every interval, so four of them
    /// can all be the same cheap one while another pool never ran its own. The real probes are
    /// wrapped to count, per source, every time one begins.
    @Test
    func theStandardProbes_beginOnEveryRealPool() async throws {
        // Given
        let began = LockedValueBox<[PoolLagMonitor.Source: Int]>([:])

        let probes = PoolLagMonitor.Probe.standard.map { probe in
            PoolLagMonitor.Probe(source: probe.source) { didBegin in
                probe.enqueue {
                    began.withLockedValue { $0[probe.source, default: 0] += 1 }
                    didBegin()
                }
            }
        }

        let monitor = PoolLagMonitor(interval: 0.01, probes: probes)

        // When
        monitor.start()
        defer { monitor.stop() }

        // Then
        try await eventually(timeout: 60) {
            let counts = began.withLockedValue { $0 }
            return probes.allSatisfy { counts[$0.source, default: 0] >= 1 }
        }

        #expect(monitor.completedProbes >= probes.count)
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
