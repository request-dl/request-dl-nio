/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct _OptionalContentTests {

    @Test
    func conditionActiveBuilder() async throws {
        // Given
        let applyCondition = true

        @PropertyBuilder
        var result: some Property {
            if applyCondition {
                BaseURL("google.com")
            }
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _OptionalContent<BaseURL>)
        #expect(resolved.request.url == "https://google.com")
        #expect(resolved.request.headers.isEmpty)
    }

    @Test
    func conditionDisableBuilder() async throws {
        // Given
        let applyCondition = false

        @PropertyBuilder
        var result: some Property {
            if applyCondition {
                BaseURL("google.com")
            }
        }

        // When
        let resolved = try await resolve(TestProperty(result))

        // Then
        #expect(result is _OptionalContent<BaseURL>)
        #expect(resolved.request.url != "https://google.com")
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = _OptionalContent<EmptyProperty>(.init())

        // Then
        try await assertNever(property.body)
    }
}
