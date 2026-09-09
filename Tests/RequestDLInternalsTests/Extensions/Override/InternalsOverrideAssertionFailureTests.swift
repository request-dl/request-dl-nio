//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if DEBUG
struct InternalsOverrideAssertionFailureTests {

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

    /// `installGlobally` is one shared, last-writer-wins slot for the whole process — the same
    /// contract a real test run relies on (whichever `.nonFatalWatchdog` suite starts first
    /// installs it for everyone). Racing this test's own install against `NonFatalWatchdogTrait`
    /// installing its own closure from a concurrently-running covered suite would make this
    /// flaky (whichever wins governs, silently), so `ensureInstalled()` joins that trait's
    /// one-time install first — it can then never fire again for the rest of the process — before
    /// this test claims the slot for itself.
    @Test
    func installGloballyInterceptsDetachedReportsAndYieldsToTaskLocalReplace() async throws {
        // Given
        NonFatalWatchdogTrait.ensureInstalled()

        // `AsyncLock.Watchdog` reports from a `Task.detached`, which does not inherit the
        // task-local override `replace(with:perform:)` relies on — this is the scenario
        // `installGlobally` exists for, so the regression has to go through a detached task
        // too, not a plain synchronous call.
        let captured = InlineProperty<String?>(wrappedValue: nil)
        let signal = AsyncSignal()

        Internals.Override.AssertionFailure.installGlobally { message, _, _ in
            captured.wrappedValue = message
            signal.signal()
        }

        // When
        Task.detached {
            Internals.assertionFailure("simulated watchdog trip")
        }

        try await signal.wait()

        // Then
        #expect(captured.wrappedValue == "🐞 RequestDL bug: simulated watchdog trip")

        // Given
        // A task-local replace must still win over the global override just installed above —
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
}
#endif
