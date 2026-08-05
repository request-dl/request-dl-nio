//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct RequestEnvironmentValuesTests {

    struct IntegerKey: RequestEnvironmentKey {
        static let defaultValue = 0
    }

    struct StringKey: RequestEnvironmentKey {
        static let defaultValue = ""
    }

    @Test
    func subscript_whenKeyNotSet_shouldReturnDefaultValue() async throws {
        // Given
        let values = RequestEnvironmentValues()

        // Then
        #expect(values[IntegerKey.self] == IntegerKey.defaultValue)
    }

    @Test
    func subscript_whenKeySet_shouldReturnStoredValue() async throws {
        // Given
        var values = RequestEnvironmentValues()

        // When
        values[IntegerKey.self] = 42

        // Then
        #expect(values[IntegerKey.self] == 42)
    }

    @Test
    func subscript_whenMultipleKeysSet_shouldNotOverlap() async throws {
        // Given
        var values = RequestEnvironmentValues()

        // When
        values[IntegerKey.self] = 7
        values[StringKey.self] = "request-dl"

        // Then
        #expect(values[IntegerKey.self] == 7)
        #expect(values[StringKey.self] == "request-dl")
    }

    @Test
    func debugDescription_whenEmpty_shouldContainEmptyMarker() async throws {
        // Given
        let values = RequestEnvironmentValues()

        // Then
        #expect(values.debugDescription == "\(RequestEnvironmentValues.self)(empty)")
    }

    @Test
    func debugDescription_whenNotEmpty_shouldDescribeStoredValues() async throws {
        // Given
        var values = RequestEnvironmentValues()

        // When
        values[IntegerKey.self] = 42

        // Then
        #expect(values.debugDescription.contains("IntegerKey"))
        #expect(values.debugDescription.contains("42"))
        #expect(!values.debugDescription.contains("(empty)"))
    }
}
