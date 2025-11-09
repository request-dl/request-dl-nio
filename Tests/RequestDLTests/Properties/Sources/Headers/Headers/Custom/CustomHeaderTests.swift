/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct CustomHeaderTests {

    @Test
    func any_whenInitWithStringValue() async throws {
        // Given
        let name = "xxx-api-key"
        let value = "password"

        // When
        let resolved = try await resolve(TestProperty {
            CustomHeader(
                name: name,
                value: value
            )
        })

        // Then
        #expect(resolved.request.headers[name] == [value])
    }

    @Test
    func any_whenInitWithLosslessValue() async throws {
        // Given
        let name = "xxx-api-key"
        let value = 123

        // When
        let resolved = try await resolve(TestProperty {
            CustomHeader(
                name: name,
                value: value
            )
        })

        // Then
        #expect(resolved.request.headers[name] == ["\(value)"])
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = CustomHeader(name: "key", value: 123)

        // Then
        try await assertNever(property.body)
    }
}
