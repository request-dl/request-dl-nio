/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class EnvironmentTests: XCTestCase {

    struct IntegerEnvironmentKey: PropertyEnvironmentKey {
        static var defaultValue: Int = .zero
    }

    struct IntegerReceiver: Property {

        @PropertyEnvironment(\.integer) var integer
        let value: @Sendable (Int) -> Void

        var body: EmptyProperty {
            value(integer)
            return EmptyProperty()
        }
    }

    func testEnvironment_whenIntegerNotSet_shouldBeZero() async throws {
        // Given
        let expectation = expectation(description: "integer.receiver")

        let value = SendableBox<Int?>(nil)

        let receiver = IntegerReceiver {
            value($0)
            expectation.fulfill()
        }

        // When
        _ = try await resolve(TestProperty {
            receiver
        })

        await fulfillment(of: [expectation])

        // Then
        XCTAssertEqual(value(), IntegerEnvironmentKey.defaultValue)
    }

    func testEnvironment_whenIntegerSet_shouldBeUpdated() async throws {
        // Given
        let expectation = expectation(description: "integer.receiver")

        let receivedValue = SendableBox<Int?>(nil)

        let receiver = IntegerReceiver {
            receivedValue($0)
            expectation.fulfill()
        }

        let value = 2

        // When
        _ = try await resolve(TestProperty {
            receiver
                .environment(\.integer, value)
        })

        await fulfillment(of: [expectation])

        // Then
        XCTAssertEqual(receivedValue(), value)
    }
}

extension PropertyEnvironmentValues {

    fileprivate var integer: Int {
        get { self[EnvironmentTests.IntegerEnvironmentKey.self] }
        set { self[EnvironmentTests.IntegerEnvironmentKey.self] = newValue }
    }
}
