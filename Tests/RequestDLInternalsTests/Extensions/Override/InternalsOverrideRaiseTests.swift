//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

#if DEBUG
struct InternalsOverrideRaiseTests {

    @Test
    func replaceSyncInterceptsRaise() {
        // Given
        let captured = InlineProperty<Int32?>(wrappedValue: nil)

        // When
        let result = Internals.Override.Raise.replace(
            with: { value in
                captured.wrappedValue = value
                return 0
            },
            perform: {
                Internals.Override.raise(42)
            }
        )

        // Then
        #expect(captured.wrappedValue == 42)
        #expect(result == 0)
    }
}
#endif
