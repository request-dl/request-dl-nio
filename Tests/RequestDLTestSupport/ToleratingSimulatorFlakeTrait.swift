//
// See LICENSE for this package's licensing information.
//

// Same reasons as `NonFatalWatchdogTrait.swift` for the conditional compilation: this is a regular
// target, built unconditionally by every `swift build`, where `Testing` isn't always available.
#if DEBUG && canImport(Testing)
import Testing

/// Records what a suite reports on an Apple *simulator* as a known issue instead of a failure, for
/// a suite whose failures there are CI noise rather than regressions.
///
/// Meant for the one case it exists for: a suite that fails intermittently, in a different test
/// each run, only on the simulator runners, and was never reproduced anywhere else (see
/// `InternalsPACEvaluatorTests`). Marking it intermittent keeps it honest in both directions: a run
/// where the suite passes is just a pass, and a run where it trips is a known issue, listed in the
/// results, not a red job nobody can act on.
///
/// Everywhere that isn't a simulator (macOS, Mac Catalyst, Linux, Android) it does nothing, so the
/// suite still fails there for real. The cost is that on a simulator a genuine regression in the
/// suite's subject no longer fails the job on its own; the other platforms are what catches it.
package struct ToleratingSimulatorFlakeTrait: TestTrait, SuiteTrait, TestScoping {

    package let reason: Comment

    package var isRecursive: Bool { true }

    package func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        #if targetEnvironment(simulator)
        await withKnownIssue(reason, isIntermittent: true) {
            try await function()
        }
        #else
        try await function()
        #endif
    }
}

extension Trait where Self == ToleratingSimulatorFlakeTrait {

    /// Records issues from the suite as known, intermittent ones on an Apple simulator, for
    /// `reason`.
    package static func toleratingSimulatorFlake(_ reason: Comment) -> Self {
        Self(reason: reason)
    }
}
#endif
