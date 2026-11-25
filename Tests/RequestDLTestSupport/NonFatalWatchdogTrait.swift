//
// See LICENSE for this package's licensing information.
//

// `RequestDLTestSupport` is a regular target, built unconditionally by every `swift build`
// (Release, Static SDK, Android, ...), not just test runs:
// - Unlike a `.testTarget`, it has no automatic access to `Testing`, and the module genuinely
//   isn't there on some of those toolchains (confirmed on the Static SDK and Android builds).
// - `Internals.Override.AssertionFailure`, which this file calls into, only exists `#if DEBUG`
//   in RequestDLInternals, so a Release build compiles this target too (confirmed on Release
//   6.2 and 6.3), where that whole type is unavailable.
// Degrading to empty rather than failing keeps this file harmless everywhere it isn't needed.
#if DEBUG && canImport(Testing)
import RequestDLInternals
import Testing

/// Makes `AsyncLock.Watchdog` trips record a ``Testing/Issue`` instead of crashing the whole
/// process.
///
/// `AsyncLock.Watchdog` reports through `Internals.assertionFailure`, which by default traps.
/// That is appropriate for a real deadlock, but not for the runner-level CPU/scheduler stalls
/// that trip it under CI simulator contention: one stalled lock would take the entire test job
/// down with it, including every other test that happened to be in flight.
///
/// `Internals.Override.AssertionFailure`'s existing task-local override can't help here,
/// since `AsyncLock`'s watchdog reports from a `Task.detached`, which does not inherit
/// task-local values, so it always sees the default. This trait installs a process-wide
/// override instead, the first time any suite carrying it runs. That install is a plain
/// `static let`, so it is idempotent and thread-safe no matter how many suites reference it
/// concurrently, and, because the override is process-wide rather than per-suite, it also
/// covers every other suite in the same test run once installed, not just the ones that carry
/// this trait.
///
/// ## A held lock on a late machine is a warning, not an error
///
/// The watchdog measures wall clock, and a lock held across an `await` on
/// `Internals.FileSystemManager`'s thread pool (on purpose) also counts the time that work spent
/// queued behind every other suite's file work. Where the whole suite is oversubscribed (the
/// URLSession-only CI job, where a trivial cache test took over a minute) that queue alone
/// outlasts the 15 s budget: the reports there all named the same `Internals.Buffer.write`
/// holder, with nobody waiting behind it. One recorded issue fails the job, so this trait records
/// an "AsyncLock held" report as a *warning* when ``PoolLagMonitor`` has seen the machine run
/// more than ``lagThreshold`` seconds late within the last ``lagWindow`` seconds (a pool starting
/// work late, at any of the priorities it probes, its own thread waking late, or a tiny file
/// write taking that long), and says so in the message. With healthy pools it stays an error,
/// since that is what a real deadlock looks like. Either way the report ends with the lag the
/// monitor saw from each source, so a report that stays an error still shows what was measured.
///
/// Only a lock held by `Internals.Buffer`'s file work (see ``isBufferFileWork(_:)``) is eligible.
/// The other locks that carry a watchdog, such as the `ClientManager` resolution lock (45 s) and
/// `Client.shutdown()` (20 s), do not wait on the file pool, so lag there says nothing about
/// them and a report from them stays an error even on a stalled runner.
package struct NonFatalWatchdogTrait: TestTrait, SuiteTrait, TestScoping {

    /// How late work has to have started, at worst, for a held lock to be put down to the machine.
    package static let lagThreshold = 5.0

    /// How far back that lateness is looked for. Longer than the lock's own 15 s budget, since
    /// the report arrives after the stall that caused it has been going on for that long.
    package static let lagWindow = 20.0

    package var isRecursive: Bool { true }

    private static let install: Void = {
        PoolLagMonitor.shared.start()

        Internals.Override.AssertionFailure.installGlobally { message, _, _ in
            let lags = PoolLagMonitor.shared.lags(within: lagWindow)

            report(message, lag: .worst(of: lags), lags: lags) {
                Issue.record(Comment(rawValue: $0), severity: $1)
            }
        }
    }()

    /// Turns a watchdog report into a recorded issue: an error, unless it is a held lock and
    /// `lag` says the machine itself was late, in which case a warning that carries the lag.
    ///
    /// `lags`, each source's worst lag, is appended to a held lock's report either way, so a
    /// report that stays an error still shows what the monitor saw.
    ///
    /// The recording is a parameter so a test can see what would be recorded without the test
    /// itself being failed by it.
    package static func report(
        _ message: String,
        lag: PoolLagMonitor.Lag,
        lags: [PoolLagMonitor.Source: Double] = [:],
        record: (String, Issue.Severity) -> Void
    ) {
        guard message.contains("AsyncLock held") else {
            record(message, .error)
            return
        }

        // Late machines are only an explanation for the locks that wait on the file pool.
        let isEligible = isBufferFileWork(message)

        let seen = PoolLagMonitor.Source.allCases.compactMap { source in
            lags[source].map { "\(source.rawValue) \(($0 * 10).rounded() / 10)s" }
        }
        let detailed =
            seen.isEmpty ? message : "\(message)\n\nLag in the last \(Int(lagWindow))s: \(seen.joined(separator: ", "))"

        guard isEligible, lag.seconds > lagThreshold, let source = lag.source else {
            record(detailed, .error)
            return
        }

        record(
            """
            \(detailed)

            Downgraded to a warning: \(source.symptom(seconds: Int(lag.seconds.rounded()))) \
            in the last \(Int(lagWindow))s (more than \(Int(lagThreshold))s), so this runner is \
            stalled and nothing here is known to be deadlocked.
            """,
            .warning
        )
    }

    /// Whether the lock in a watchdog `message` is held by `Internals.Buffer`'s file work, the one
    /// holder a late machine can explain.
    ///
    /// The report names the holder as `holder: <operation> (<function> at <file>:<line>)`, so the
    /// rule is on the holder's *file*, not on the whole message and not on a line number, which
    /// moves with every edit to that file. Only the `holder:` line is read: a call site that
    /// merely waits behind another one (`pending`) does not count. Every `Internals.Buffer.swift`
    /// operation qualifies (`write(at:data:)` is the one that reported in the URLSession-only
    /// job, `read(at:length:)` the other), since they all hold the lock across the same file pool.
    package static func isBufferFileWork(_ message: String) -> Bool {
        message
            .split(whereSeparator: \.isNewline)
            .first { $0.drop { $0 == " " }.hasPrefix("holder:") }
            .map { $0.contains("Internals.Buffer.swift:") } ?? false
    }

    /// Forces the one-time install to run now, if it hasn't already.
    ///
    /// `installGlobally` always overwrites, by design, so the *last* thing to call it governs
    /// for the rest of the process. A test that wants to install its own distinguishable closure
    /// and reliably observe it win therefore needs this trait's install to be unable to fire
    /// *after* that point. Calling this first joins the one-time `static let` (thread-safe: every
    /// caller either runs the initializer once or blocks until whoever is already running it
    /// finishes), so once it returns, nothing tied to this trait will ever call
    /// `installGlobally` again for the rest of the process.
    package static func ensureInstalled() {
        _ = install
    }

    package func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        _ = Self.install
        try await function()
    }
}

extension Trait where Self == NonFatalWatchdogTrait {

    /// Records `AsyncLock.Watchdog` trips as a test issue instead of crashing the process.
    package static var nonFatalWatchdog: Self { Self() }
}
#endif
