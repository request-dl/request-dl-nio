//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDLInternals

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
}
#endif
