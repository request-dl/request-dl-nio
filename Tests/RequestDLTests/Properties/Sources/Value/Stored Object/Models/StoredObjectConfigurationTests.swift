//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct StoredObjectConfigurationTests {

    final class Counter: @unchecked Sendable {
        var value = 0
    }

    struct WithStoredObject: Property {

        @StoredObject var counter = Counter()

        var body: some Property {
            EmptyProperty()
        }
    }

    @Test
    func storedObject_whenAccessedWithoutGraphTraversal_shouldFallBackToGlobalConfiguration() async throws {
        // Given
        let property = WithStoredObject()

        // When
        let first = property.counter
        let second = property.counter

        // Then
        #expect(first === second)
    }

    @Test
    func storedObject_whenTwoInstancesAccessedWithoutGraphTraversal_shouldShareGlobalStorage() async throws {
        // Given
        let first = WithStoredObject()
        let second = WithStoredObject()

        // Then
        #expect(first.counter === second.counter)
    }
}
