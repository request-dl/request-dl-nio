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
/// - a `Task.detached` (the same hop the watchdog itself makes)
///
/// to *begin* running, and remembers the worst of the last `retention` seconds. A probe that has
/// not begun yet counts for however long it has been waiting, so a pool that is stuck right now
/// is visible while it is still stuck, not once it recovers.
///
/// The monitor never waits on a probe, so it cannot itself hang, and it never has more than one
/// probe of each kind in flight, so a stalled pool does not make it pile work onto that pool.
package final class PoolLagMonitor: @unchecked Sendable {

    /// What got probed.
    package enum Source: String, Sendable, CaseIterable {
        case filePool = "file pool"
        case cooperativePool = "cooperative pool"
    }

    /// How late work started.
    package struct Lag: Sendable, Equatable {

        package var seconds: Double
        package var source: Source?

        package static let none = Lag(seconds: 0, source: nil)
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

    /// The worst lag seen within the last `window` seconds, counting any probe that has been
    /// waiting to begin for that long so far. ``Lag/none`` if there is none.
    package func worstLag(within window: Double) -> Lag {
        let current = now()
        let windowNanoseconds = Self.nanoseconds(window)

        return lock.withLock {
            var worst = Lag.none

            for sample in _state.samples where current &- sample.recordedAt <= windowNanoseconds {
                let seconds = Double(sample.nanoseconds) / 1_000_000_000

                if seconds > worst.seconds {
                    worst = Lag(seconds: seconds, source: sample.source)
                }
            }

            for (source, startedAt) in _state.pending {
                let seconds = Double(current &- startedAt) / 1_000_000_000

                if seconds > worst.seconds {
                    worst = Lag(seconds: seconds, source: source)
                }
            }

            return worst
        }
    }

    // MARK: - Private methods

    private func run() {
        while true {
            let isStopped = lock.withLock { _state.isStopped }

            if isStopped {
                return
            }

            tick()

            // Woken early only by ``stop()``.
            if wake.wait(timeout: .now() + interval) == .success {
                return
            }
        }
    }

    private func began(_ source: Source) {
        let current = now()

        lock.withLock {
            guard let startedAt = _state.pending.removeValue(forKey: source) else {
                return
            }

            _state.completed += 1
            _state.samples.append(Sample(recordedAt: current, nanoseconds: current &- startedAt, source: source))

            let horizon = Self.nanoseconds(retention)
            _state.samples.removeAll { current &- $0.recordedAt > horizon }
        }
    }

    private static func nanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}
#endif
