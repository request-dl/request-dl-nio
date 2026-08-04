//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct _ContainerTests {

    @Test
    func container_whenInitWithWrappedValue_shouldStoreAndUpdateValue() {
        // Given
        let container = _Container<Int>(wrappedValue: 42)

        // Then
        #expect(container.wrappedValue == 42)

        // When
        container.wrappedValue = 7

        // Then
        #expect(container.wrappedValue == 7)
    }

    @Test
    func container_whenInitWithoutWrappedValue_shouldDefaultToNil() {
        // Given
        let container = _Container<Int?>()

        // Then
        #expect(container.wrappedValue == nil)

        // When
        container.wrappedValue = 5

        // Then
        #expect(container.wrappedValue == 5)
    }
}
