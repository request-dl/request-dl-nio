/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct EnvironmentTests {

    struct IntegerEnvironmentKey: RequestEnvironmentKey {
        static var defaultValue: Int { .zero }
    }

    struct IntegerReceiver: Property {

        @PropertyEnvironment(\.integer) var integer
        let value: @Sendable (Int) -> Void

        var body: EmptyProperty {
            value(integer)
            return EmptyProperty()
        }
    }

    @Test
    func environment_whenIntegerNotSet_shouldBeZero() async throws {
        // Given
        let expectation = AsyncSignal()

        let value = InlineProperty<Int?>(wrappedValue: nil)

        let receiver = IntegerReceiver {
            value.wrappedValue = $0
            expectation.signal()
        }

        // When
        _ = try await resolve(TestProperty {
            receiver
        })

        await expectation.wait()

        // Then
        #expect(value.wrappedValue == IntegerEnvironmentKey.defaultValue)
    }

    @Test
    func environment_whenIntegerSet_shouldBeUpdated() async throws {
        // Given
        let expectation = AsyncSignal()

        let receivedValue = InlineProperty<Int?>(wrappedValue: nil)

        let receiver = IntegerReceiver {
            receivedValue.wrappedValue = $0
            expectation.signal()
        }

        let value = 2

        // When
        _ = try await resolve(TestProperty {
            receiver
                .environment(\.integer, value)
        })

        await expectation.wait()

        // Then
        #expect(receivedValue.wrappedValue == value)
    }
}

extension RequestEnvironmentValues {

    fileprivate var integer: Int {
        get { self[EnvironmentTests.IntegerEnvironmentKey.self] }
        set { self[EnvironmentTests.IntegerEnvironmentKey.self] = newValue }
    }
}
