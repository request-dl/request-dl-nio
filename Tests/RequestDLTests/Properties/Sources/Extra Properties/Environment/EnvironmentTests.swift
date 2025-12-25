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

        let value = SendableBox<Int?>(nil)

        let receiver = IntegerReceiver {
            value($0)
            expectation.signal()
        }

        // When
        _ = try await resolve(TestProperty {
            receiver
        })

        await expectation.wait()

        // Then
        #expect(value() == IntegerEnvironmentKey.defaultValue)
    }

    @Test
    func environment_whenIntegerSet_shouldBeUpdated() async throws {
        // Given
        let expectation = AsyncSignal()

        let receivedValue = SendableBox<Int?>(nil)

        let receiver = IntegerReceiver {
            receivedValue($0)
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
        #expect(receivedValue() == value)
    }
}

extension RequestEnvironmentValues {

    fileprivate var integer: Int {
        get { self[EnvironmentTests.IntegerEnvironmentKey.self] }
        set { self[EnvironmentTests.IntegerEnvironmentKey.self] = newValue }
    }
}
