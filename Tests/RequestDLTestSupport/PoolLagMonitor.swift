//
// See LICENSE for this package's licensing information.
//

// Same conditional compilation, for the same reasons, as `NonFatalWatchdogTrait.swift`: this is
// a regular target built by every `swift build`, and the only thing that reads the monitor is
// that trait.
#if DEBUG && canImport(Testing)
import Dispatch
import Foundation
import RequestDLInternals
import SwiftAsyncStream

/// Measures how late a loaded runner starts the work it is handed, so a stalled machine can be
/// told apart from a stalled lock.
///
/// `AsyncLock`'s watchdog measures wall clock: it reports whenever one operation has held the
/// lock for longer than its budget, whatever the operation was waiting for. A lock held across
/// an `await` on `Internals.FileSystemManager`'s thread pool (on purpose, see `Internals.Buffer`)
/// also counts the time the work spent *queued* behind every other suite's file work, and on an
/// oversubscribed CI runner that queue alone can outlast the budget. Nothing is deadlocked
/// there; the machine is late.
///
/// So every `interval` this probes, from a thread of its own (an OS thread, which neither pool
/// can starve), how long it takes for
/// - a closure handed to `Internals.FileSystemManager.run`, and
/// - a `Task.detached` (the same hop the watchdog itself makes), at the default priority and at
///   the two lower ones this package runs lock-holding work at (`.utility`, `.background`)
///
/// to *begin* running, and remembers the worst of the last `retention` seconds. A probe that has
/// not begun yet counts for however long it has been waiting, so a pool that is stuck right now
/// is visible while it is still stuck, not once it recovers.
///
/// Two stalls never show in how late a pool *starts* work, so they are watched for too:
/// - The whole process (or machine) not running at all, monitor thread included. Every probe has
///   long begun by the time such a freeze starts, so none is pending through it, and once it ends
///   the next probes begin on time. What does show is the monitor's own thread waking late: it
///   asks for a wake-up every `interval`, so a gap far beyond that is a freeze. The gap counts
///   while it is still open, too (from the last wake-up until now), so a watchdog report that
///   wakes up from the same freeze *before* the monitor does already sees it.
/// - A file system that accepts work on time but takes ages to finish it. One probe therefore
///   writes (and removes) a one-byte file on the file pool, and counts until that is done.
///
/// The probes at a lower priority are what the URLSession-only and iPadOS CI jobs needed: a
/// dozen independent locks reported at once, each held by one `Internals.Buffer.write` with
/// nobody waiting behind it, while the default-priority probe and the monitor's own thread were
/// both on time. On Darwin a priority is only given a cooperative thread once no higher one has
/// work waiting, so a busy run of `.medium` tests can keep `.background` work (such as
/// `DataCache`'s writes) off the pool for longer than the lock's budget, without anything at
/// `.medium` ever starting late.
///
/// The monitor never waits on a probe, so it cannot itself hang, and it never has more than one
/// probe of each kind in flight, so a stalled pool does not make it pile work onto that pool.
package final class PoolLagMonitor: @unchecked Sendable {

    /// What got probed.
    package enum Source: String, Sendable, CaseIterable {
        case filePool = "file pool"
        case cooperativePool = "cooperative pool"
        case utilityTasks = "cooperative pool at utility priority"
        case backgroundTasks = "cooperative pool at background priority"
        case monitorThread = "lag monitor's own thread"
        case fileWrite = "file write"

        /// What a lag of `seconds` from this source means, for a report to say.
        package func symptom(seconds: Int) -> String {
            switch self {
            case .filePool, .cooperativePool, .utilityTasks, .backgroundTasks:
                return "work handed to the \(rawValue) started about \(seconds)s late"
            case .monitorThread:
                return "the \(rawValue) woke about \(seconds)s late"
            case .fileWrite:
                return "a one-byte \(rawValue) on the file pool took about \(seconds)s"
            }
        }
    }

    /// How late work started.
    package struct Lag: Sendable, Equatable {

        package var seconds: Double
        package var source: Source?

        package static let none = Lag(seconds: 0, source: nil)

        /// The worst of `lags`, each source's worst lag, or ``none`` if there is none.
        package static func worst(of lags: [Source: Double]) -> Lag {
            var worst = Lag.none

            // In `allCases` order, so a tie names the same source every time.
            for source in Source.allCases {
                if let seconds = lags[source], seconds > worst.seconds {
                    worst = Lag(seconds: seconds, source: source)
                }
            }

            return worst
        }
    }

    /// One thing to probe: `enqueue` must hand the closure it is given to whatever it measures,
    /// and the closure is called once the work has begun running there.
    package struct Probe: Sendable {

        package var source: Source
        package var enqueue: @Sendable (_ began: @escaping @Sendable () -> Void) -> Void

        package init(
            source: Source,
            enqueue: @escaping @Sendable (_ began: @escaping @Sendable () -> Void) -> Void
        ) {
            self.source = source
            self.enqueue = enqueue
        }

        /// The probes a real run uses.
        package static let standard: [Probe] = [
            Probe(source: .filePool) { began in
                Task.detached {
                    _ = try? await Internals.FileSystemManager.run { began() }
                }
            },
            Probe(source: .cooperativePool) { began in
                Task.detached { began() }
            },
            // The probe above runs at `.medium`, the priority the tests themselves run at, and
            // on Darwin a lower priority only gets a cooperative thread once no higher priority
            // work is waiting: a steady stream of short `.medium` jobs, each of which the probe
            // above sees begin on time, can keep `.background` work from running at all for
            // longer than the lock's budget. That is where the locks that outlast it are held:
            // `DataCache`'s writes and a cached body's replay run at `.background`, and a
            // download's bytes go through a `.utility` `Internals.AsyncQueue`.
            Probe(source: .utilityTasks) { began in
                Task.detached(priority: .utility) { began() }
            },
            Probe(source: .backgroundTasks) { began in
                Task.detached(priority: .background) { began() }
            },
            Probe(source: .fileWrite) { began in
                Task.detached {
                    _ = try? await Internals.FileSystemManager.run {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                            "RequestDLTestSupport.PoolLagMonitor.\(ProcessInfo.processInfo.processIdentifier)"
                        )

                        try? Data([0]).write(to: url)
                        try? FileManager.default.removeItem(at: url)
                        began()
                    }
                }
            },
        ]
    }

    /// The process-wide monitor, idle until ``start()`` is called.
    package static let shared = PoolLagMonitor()

    private struct Sample {
        var recordedAt: UInt64
        var nanoseconds: UInt64
        var source: Source
    }

    private struct State {
        var samples: [Sample] = []
        var pending: [Source: UInt64] = [:]
        var completed = 0
        var lastHeartbeat: UInt64?
        var isStarted = false
        var isStopped = false
    }

    private let interval: Double
    private let retention: Double
    private let probes: [Probe]
    private let now: @Sendable () -> UInt64

    private let lock = Lock()
    private var _state = State()
    private let wake = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)

    package init(
        interval: Double = 0.25,
        retention: Double = 30,
        probes: [Probe] = Probe.standard,
        now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.interval = interval
        self.retention = retention
        self.probes = probes
        self.now = now
    }

    /// How many probes have begun, in all.
    package var completedProbes: Int {
        lock.withLock { _state.completed }
    }

    // MARK: - Package methods

    /// Starts probing, once: calling it again, from anywhere, does nothing.
    package func start() {
        let shouldStart = lock.withLock { () -> Bool in
            guard !_state.isStarted, !_state.isStopped else {
                return false
            }

            _state.isStarted = true
            return true
        }

        // TEMPORARY (CI diagnosis, do not merge).
        print("[TMP-CI PoolLagMonitor] started at \(DispatchTime.now().uptimeNanoseconds / 1_000_000)ms")

        guard shouldStart else {
            return
        }

        let thread = Thread { [self] in
            run()
            finished.signal()
        }

        thread.name = "RequestDLTestSupport.PoolLagMonitor"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Stops probing and, if it was ever started, waits for the thread to finish. For monitors
    /// a test makes for itself; the shared one runs for the life of the process.
    package func stop() {
        let wasStarted = lock.withLock { () -> Bool in
            let wasStarted = _state.isStarted && !_state.isStopped
            _state.isStopped = true
            return wasStarted
        }

        guard wasStarted else {
            return
        }

        wake.signal()
        finished.wait()
    }

    /// Runs one probing round on the calling thread: starts a probe of each kind that has none in
    /// flight. ``start()`` calls this on its own thread every `interval`; it is exposed so a
    /// test can drive the monitor without a thread or a wait.
    package func tick() {
        for probe in probes {
            let isIdle = lock.withLock { () -> Bool in
                guard _state.pending[probe.source] == nil else {
                    return false
                }

                _state.pending[probe.source] = now()
                return true
            }

            guard isIdle else {
                continue
            }

            probe.enqueue { [weak self] in
                self?.began(probe.source)
            }
        }
    }

    /// Records that the monitor's thread is running, now. ``start()``'s thread calls this every
    /// time it wakes; it is exposed so a test can drive the monitor without a thread or a wait.
    ///
    /// A gap since the previous heartbeat longer than `interval` is recorded as a sample of how
    /// much longer, and until the next heartbeat ``worstLag(within:)`` counts the gap that is
    /// still open. The two happen under one lock, so a reader sees one or the other.
    package func heartbeat() {
        let intervalNanoseconds = Self.nanoseconds(interval)

        lock.withLock {
            // Read under the lock, like every other timestamp the state keeps, so a reader never
            // sees one later than its own `now()` (which would wrap the subtraction around).
            let current = now()

            if let last = _state.lastHeartbeat {
                let gap = current &- last

                if gap > intervalNanoseconds {
                    _state.samples.append(
                        Sample(recordedAt: current, nanoseconds: gap - intervalNanoseconds, source: .monitorThread)
                    )
                }
            }

            _state.lastHeartbeat = current
            _prune(at: current)
        }
    }

    /// The worst lag seen within the last `window` seconds, counting any probe that has been
    /// waiting to begin for that long so far. ``Lag/none`` if there is none.
    package func worstLag(within window: Double) -> Lag {
        Lag.worst(of: lags(within: window))
    }

    /// The worst lag of each source within the last `window` seconds, counted the way
    /// ``worstLag(within:)`` counts it. A source with nothing late is missing.
    package func lags(within window: Double) -> [Source: Double] {
        let windowNanoseconds = Self.nanoseconds(window)

        return lock.withLock {
            // Under the lock: a heartbeat or a tick stamped after a `now()` read outside it would
            // be later than `current`, and `current &- it` would wrap to a huge, false lag.
            let current = now()
            var lags: [Source: Double] = [:]

            func note(_ seconds: Double, from source: Source) {
                if seconds > lags[source, default: 0] {
                    lags[source] = seconds
                }
            }

            for sample in _state.samples where current &- sample.recordedAt <= windowNanoseconds {
                note(Double(sample.nanoseconds) / 1_000_000_000, from: sample.source)
            }

            if let last = _state.lastHeartbeat, !_state.isStopped {
                let overdue = current &- last
                let intervalNanoseconds = Self.nanoseconds(interval)

                if overdue > intervalNanoseconds {
                    note(Double(overdue - intervalNanoseconds) / 1_000_000_000, from: .monitorThread)
                }
            }

            for (source, startedAt) in _state.pending {
                note(Double(current &- startedAt) / 1_000_000_000, from: source)
            }

            return lags
        }
    }

    // MARK: - Private methods

    private func run() {
        // TEMPORARY (CI diagnosis, do not merge).
        var tmpRounds = 0

        while true {
            tmpRounds += 1

            if tmpRounds % 20 == 0 {
                print(
                    "[TMP-CI PoolLagMonitor] at \(DispatchTime.now().uptimeNanoseconds / 1_000_000)ms lags(5s)=\(lags(within: 5))"
                )
            }

            let isStopped = lock.withLock { _state.isStopped }

            if isStopped {
                return
            }

            heartbeat()
            tick()

            // Woken early only by ``stop()``.
            if wake.wait(timeout: .now() + interval) == .success {
                return
            }
        }
    }

    private func began(_ source: Source) {
        lock.withLock {
            // Under the lock, for the same reason as in ``worstLag(within:)``.
            let current = now()

            guard let startedAt = _state.pending.removeValue(forKey: source) else {
                return
            }

            _state.completed += 1
            _state.samples.append(Sample(recordedAt: current, nanoseconds: current &- startedAt, source: source))
            _prune(at: current)
        }
    }

    /// - Warning: Lockless. The caller must be holding ``lock``.
    private func _prune(at current: UInt64) {
        let horizon = Self.nanoseconds(retention)
        _state.samples.removeAll { current &- $0.recordedAt > horizon }
    }

    private static func nanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}
#endif
