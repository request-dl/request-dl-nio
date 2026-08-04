//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct PropertyEnvironmentTests {

    struct IntegerEnvironmentKey: RequestEnvironmentKey {
        static var defaultValue: Int { 42 }
    }

    @Test
    func wrappedValue_whenNeverUpdatedThroughAGraph_fallsBackToEnvironmentDefault() {
        // Given
        let wrapper = PropertyEnvironment(\.propertyEnvironmentTestsInteger)

        // Then
        // `update(_:)` — the only thing that ever populates the wrapper's own storage — is
        // never called here, so `wrappedValue` has to fall back to a fresh
        // `RequestEnvironmentValues()`'s own default rather than trap.
        #expect(wrapper.wrappedValue == IntegerEnvironmentKey.defaultValue)
    }
}

extension RequestEnvironmentValues {

    fileprivate var propertyEnvironmentTestsInteger: Int {
        get { self[PropertyEnvironmentTests.IntegerEnvironmentKey.self] }
        set { self[PropertyEnvironmentTests.IntegerEnvironmentKey.self] = newValue }
    }
}
