//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if DEBUG
/// Serialized because two of these tests take the process-wide slot for a while.
@Suite(.serialized)
struct InternalsOverrideAssertionFailureTests {

    private typealias Closure = Internals.Override.AssertionFailure.Closure

    /// A global replacement that acts on the reports that contain `marker` and hands every other
    /// one to whatever `forward` holds by then (what the slot held before). The suites running
    /// beside these tests report through the same slot, and must not lose theirs to it.
    private static func closure(
        for marker: String,
        forward: InlineProperty<Closure?>,
        _ body: @escaping @Sendable (String) -> Void
    ) -> Closure {
        { message, file, line in
            guard message.contains(marker) else {
                forward.wrappedValue?(message, file, line)
                return
            }

            body(message)
        }
    }

    @Test
    func replaceAsyncInterceptsAssertionFailure() async {
        // Given
        let captured = InlineProperty<(String, StaticString, UInt)?>(wrappedValue: nil)

        // When
        // The `perform` closure genuinely suspends so overload resolution picks the async
        // `replace` overload, not the sync one that would also accept a non-throwing literal.
        await Internals.Override.AssertionFailure.replace { message, file, line in
            captured.wrappedValue = (message, file, line)
        } perform: {
            try? await Task.sleep(nanoseconds: 1)
            Internals.assertionFailure("something went wrong")
        }

        // Then
        #expect(captured.wrappedValue?.0 == "🐞 RequestDL bug: something went wrong")
    }

    @Test
    func replaceSyncInterceptsAssertionFailure() {
        // Given
        let captured = InlineProperty<String?>(wrappedValue: nil)

        // When
        Internals.Override.AssertionFailure.replace { message, _, _ in
            captured.wrappedValue = message
        } perform: {
            Internals.Override.assertionFailure("plain message")
        }

        // Then
        #expect(captured.wrappedValue == "plain message")
    }

    /// `installGlobally` is one shared, last-writer-wins slot for the whole process, the same
    /// contract a real test run relies on (whichever `.nonFatalWatchdog` suite starts first
    /// installs it for everyone). Racing this test's own install against `NonFatalWatchdogTrait`
    /// installing its own closure from a concurrently-running covered suite would make this
    /// flaky (whichever wins governs, silently), so `ensureInstalled()` joins that trait's
    /// one-time install first, which can then never fire again for the rest of the process,
    /// before this test claims the slot for itself.
    @Test
    func installGloballyInterceptsDetachedReportsAndYieldsToTaskLocalReplace() async throws {
        // Given
        NonFatalWatchdogTrait.ensureInstalled()

        // `AsyncLock.Watchdog` reports from a `Task.detached`, which does not inherit the
        // task-local override `replace(with:perform:)` relies on. This is the scenario
        // `installGlobally` exists for, so the test has to go through a detached task too, not a
        // plain synchronous call.
        let captured = InlineProperty<String?>(wrappedValue: nil)
        let signal = AsyncSignal()

        // The slot is the whole process's, so what was in it comes back when this test is done:
        // left in place, every later `Internals.assertionFailure` of a detached task (the lock
        // watchdog's) in the rest of the test run would land in `captured` and be told to no one,
        // and the trait's closure, the one that turns it into a test issue, would never run again.
        // Until then, a report that is not this test's own goes on to that closure, so that the
        // suites running beside this one are not blind for its duration.
        let forward = InlineProperty<Closure?>(wrappedValue: nil)
        let replaced = Internals.Override.AssertionFailure.installGlobally(
            Self.closure(for: "simulated watchdog trip", forward: forward) { message in
                captured.wrappedValue = message
                signal.signal()
            }
        )
        forward.wrappedValue = replaced
        defer { Internals.Override.AssertionFailure.installGlobally(replaced) }

        // When
        Task.detached {
            Internals.assertionFailure("simulated watchdog trip")
        }

        try await signal.wait()

        // Then
        #expect(captured.wrappedValue == "🐞 RequestDL bug: simulated watchdog trip")

        // Given
        // A task-local replace must still win over the global override just installed above,
        // otherwise every other test relying on replace(with:perform:) to capture a specific
        // failure would silently observe nothing once any global override exists.
        let taskLocalCaptured = InlineProperty<String?>(wrappedValue: nil)

        // When
        Internals.Override.AssertionFailure.replace { message, _, _ in
            taskLocalCaptured.wrappedValue = message
        } perform: {
            Internals.assertionFailure("task-local should win")
        }

        // Then
        #expect(taskLocalCaptured.wrappedValue == "🐞 RequestDL bug: task-local should win")
    }

    /// What `installGlobally` hands back is what was there, and handing it back in puts it there
    /// again: the way a test that needs the slot for a while gives it back.
    @Test
    func installGloballyReturnsTheClosureItReplaced_andInstallingItAgainRestoresIt() async throws {
        // Given
        NonFatalWatchdogTrait.ensureInstalled()

        let first = InlineProperty<String?>(wrappedValue: nil)
        let second = InlineProperty<String?>(wrappedValue: nil)
        let signalFirst = AsyncSignal()
        let signalSecond = AsyncSignal()

        let forward = InlineProperty<Closure?>(wrappedValue: nil)
        let original = Internals.Override.AssertionFailure.installGlobally(
            Self.closure(for: "the first is back", forward: forward) { message in
                first.wrappedValue = message
                signalFirst.signal()
            }
        )
        forward.wrappedValue = original
        defer { Internals.Override.AssertionFailure.installGlobally(original) }

        // The trait's closure was in the slot, whatever suite ran first.
        #expect(original != nil)

        // When
        let replaced = Internals.Override.AssertionFailure.installGlobally(
            Self.closure(for: "the second is installed", forward: forward) { message in
                second.wrappedValue = message
                signalSecond.signal()
            }
        )

        Task.detached { Internals.assertionFailure("while the second is installed") }
        try await signalSecond.wait()

        // Then: what it replaced is what this test installed, and the report went to the new one.
        #expect(replaced != nil)
        #expect(first.wrappedValue == nil)
        #expect(second.wrappedValue == "🐞 RequestDL bug: while the second is installed")

        // When
        Internals.Override.AssertionFailure.installGlobally(replaced)
        Task.detached { Internals.assertionFailure("after the first is back") }
        try await signalFirst.wait()

        // Then
        #expect(first.wrappedValue == "🐞 RequestDL bug: after the first is back")
        #expect(second.wrappedValue == "🐞 RequestDL bug: while the second is installed")
    }
}
#endif
