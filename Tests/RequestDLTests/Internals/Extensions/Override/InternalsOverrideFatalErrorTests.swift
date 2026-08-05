//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if DEBUG
struct InternalsOverrideFatalErrorTests {

    @Test
    func replaceAsyncSwapsClosureForDurationOfOperation() async {
        // Given
        let value: Int

        // When
        // The `perform` closure genuinely suspends so overload resolution picks the async
        // `replace` overload, not the sync one covered by `_EitherContentTests.assertNever`.
        value = await Internals.Override.FatalError.replace { message, file, line in
            Swift.fatalError(message, file: file, line: line)
        } perform: {
            try? await Task.sleep(nanoseconds: 1)
            return 42
        }

        // Then
        #expect(value == 42)
    }
}
#endif
