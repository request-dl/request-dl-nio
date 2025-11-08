/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import AsyncHTTPClient
@testable import RequestDL

struct UserAgentHeaderTests {

    @Test
    func agent_whenNoValueIsSet() async throws {
        // Given
        let property = TestProperty(EmptyProperty())

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(resolved.request.headers["User-Agent"] == nil)
    }

    @Test
    func agent_whenValueIsSetWithAddStrategy() async throws {
        // Given
        let userAgent = "A text agent specification"

        // When
        let resolved = try await resolve(TestProperty {
            UserAgentHeader(userAgent)
        })

        // Then
        #expect(resolved.request.headers["User-Agent"] == [userAgent])
    }

    @Test
    func agent_whenUsingDefaultValue() async throws {
        // Given
        let property = TestProperty {
            UserAgentHeader()
        }

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(resolved.request.headers["User-Agent"] == [ProcessInfo.processInfo.userAgent])
    }

    @Test
    func agent_whenUsingDefaultValueWithCustomAgent() async throws {
        // Given
        let userAgent = "CustomAgent"
        // When
        let resolved = try await resolve(TestProperty {
            HeaderGroup {
                UserAgentHeader()
                UserAgentHeader(userAgent)
            }
            .headerStrategy(.adding)
        })

        // Then
        #expect(
            resolved.request.headers["User-Agent"],
            [ProcessInfo.processInfo.userAgent + " \(userAgent)"]
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = UserAgentHeader("CustomAgent/1.0.0")

        // Then
        try await assertNever(property.body)
    }
}
