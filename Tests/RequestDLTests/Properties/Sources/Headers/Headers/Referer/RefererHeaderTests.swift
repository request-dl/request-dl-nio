/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct RefererHeaderTests {

    @Test
    func referer() async throws {
        let property = TestProperty(RefererHeader("https://www.example.com/"))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.headers["Referer"] == ["https://www.example.com/"])
    }

    @Test
    func refererWithHTML() async throws {
        let property = TestProperty(RefererHeader("https://www.example.com/page1.html"))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.headers["Referer"] == ["https://www.example.com/page1.html"])
    }

    @Test
    func refererWithPathAndQuery() async throws {
        let property = TestProperty(RefererHeader("https://www.google.com/search?q=apple"))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.headers["Referer"] == ["https://www.google.com/search?q=apple"])
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = RefererHeader("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
