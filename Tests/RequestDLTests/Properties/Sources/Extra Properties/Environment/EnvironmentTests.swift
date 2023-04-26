/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable @_spi(Private) import RequestDL

class EnvironmentTests: XCTestCase {

    struct IntegerEnvironmentKey: EnvironmentKey {
        static var defaultValue: Int = .zero
    }

    struct IntegerReceiver: Property {

        let value: (Int) -> Void

        var body: Never {
            bodyException()
        }

        static func _makeProperty(
            property: _GraphValue<EnvironmentTests.IntegerReceiver>,
            inputs: _PropertyInputs
        ) async throws -> _PropertyOutputs {
            property.assertIfNeeded()
            property.value(inputs.environment.integer)
            return .init(EmptyLeaf())
        }
    }

    func testEnvironment_whenIntegerNotSet_shouldBeZero() async throws {
        // Given
        let expectation = expectation(description: "integer.receiver")

        var value: Int?
        let receiver = IntegerReceiver {
            value = $0
            expectation.fulfill()
        }

        // When
        _ = try await resolve(TestProperty {
            receiver
        })

        await fulfillment(of: [expectation])

        // Then
        XCTAssertEqual(value, IntegerEnvironmentKey.defaultValue)
    }

    func testEnvironment_whenIntegerSet_shouldBeUpdated() async throws {
        // Given
        let expectation = expectation(description: "integer.receiver")

        var receivedValue: Int?
        let receiver = IntegerReceiver {
            receivedValue = $0
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
        XCTAssertEqual(receivedValue, value)
    }
}

extension EnvironmentValues {

    fileprivate var integer: Int {
        get { self[EnvironmentTests.IntegerEnvironmentKey.self] }
        set { self[EnvironmentTests.IntegerEnvironmentKey.self] = newValue }
    }
}
