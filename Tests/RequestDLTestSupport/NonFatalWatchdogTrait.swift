//
// See LICENSE for this package's licensing information.
//

// `RequestDLTestSupport` is a regular target, built unconditionally by every `swift build`
// (Release, Static SDK, Android, ...), not just test runs:
// - Unlike a `.testTarget`, it has no automatic access to `Testing`, and the module genuinely
//   isn't there on some of those toolchains (confirmed on the Static SDK and Android builds).
// - `Internals.Override.AssertionFailure`, which this file calls into, only exists `#if DEBUG`
//   in RequestDLInternals — a Release build compiles this target too (confirmed on Release 6.2
//   and 6.3), where that whole type is unavailable.
// Degrading to empty rather than failing keeps this file harmless everywhere it isn't needed.
#if DEBUG && canImport(Testing)
import RequestDLInternals
import Testing

/// Makes `AsyncLock.Watchdog` trips record a ``Testing/Issue`` instead of crashing the whole
/// process.
///
/// `AsyncLock.Watchdog` reports through `Internals.assertionFailure`, which by default traps —
/// appropriate for a real deadlock, but not for the runner-level CPU/scheduler stalls that trip
/// it under CI simulator contention (see the request-dl-nio CI-flakiness issue tracking
/// `AsyncLock.Watchdog` false positives): one stalled lock then takes the entire test job down
/// with it, including every other test that happened to be in flight.
///
/// `Internals.Override.AssertionFailure`'s existing task-local override can't help here —
/// `AsyncLock`'s watchdog reports from a `Task.detached`, which does not inherit task-local
/// values, so it always sees the default. This trait installs a process-wide override instead,
/// the first time any suite carrying it runs. That install is a plain `static let`, so it is
/// idempotent and thread-safe no matter how many suites reference it concurrently, and — because
/// the override is process-wide rather than per-suite — it also covers every other suite in the
/// same test run once installed, not just the ones that carry this trait.
package struct NonFatalWatchdogTrait: TestTrait, SuiteTrait, TestScoping {

    package var isRecursive: Bool { true }

    private static let install: Void = {
        Internals.Override.AssertionFailure.installGlobally { message, _, _ in
            Issue.record(Comment(rawValue: message))
        }
    }()

    /// Forces the one-time install to run now, if it hasn't already.
    ///
    /// `installGlobally` always overwrites — by design, so the *last* thing to call it governs
    /// for the rest of the process — which means a test that wants to install its own
    /// distinguishable closure and reliably observe it win needs this trait's install to be
    /// unable to fire *after* that point. Calling this first joins the one-time `static let`
    /// (thread-safe: every caller either runs the initializer once or blocks until whoever is
    /// already running it finishes), so once it returns, nothing tied to this trait will ever
    /// call `installGlobally` again for the rest of the process.
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
